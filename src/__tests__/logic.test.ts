import { describe, expect, it } from 'vitest'
import { classifyCode, isbn10to13, isValidEan13, isValidIsbn10 } from '../logic/isbn'
import { applyFilters, EMPTY_FILTERS, findDuplicate, fold, mergeItems, normalizeItem, parseImport, sortItems, summarizePlaces, titleKey, toCSV, toExport } from '../logic/items'
import { matchScore } from '../logic/lookup'
import { toDraft } from '../logic/recognized'

const item = (p: Record<string, unknown>) => normalizeItem({ title: 'x', ...p } as never, '2026-01-01T00:00:00.000Z')

describe('isbn', () => {
  it('validates and converts', () => {
    expect(isValidIsbn10('3446205799')).toBe(true)
    expect(isValidIsbn10('344620579X')).toBe(false)
    expect(isbn10to13('3446205799')).toBe('9783446205796')
    expect(isValidEan13('9783446205796')).toBe(true)
    expect(isValidEan13('9783446205797')).toBe(false)
  })
  it('classifies codes', () => {
    expect(classifyCode('978-3-446-20579-6')).toEqual({ type: 'isbn', code: '9783446205796' })
    expect(classifyCode('3-446-20579-9')).toEqual({ type: 'isbn', code: '9783446205796' })
    expect(classifyCode('4006381333931')).toEqual({ type: 'ean', code: '4006381333931' })
    expect(classifyCode('724384260521')).toEqual({ type: 'ean', code: '724384260521' })
    expect(classifyCode('12345').type).toBe('invalid')
  })
})

describe('normalizeItem', () => {
  it('fills defaults and drops junk', () => {
    const i = normalizeItem({ title: ' Open City ', author: 'Teju Cole', kind: 'spaceship', rating: 9, foo: 1 } as never)
    expect(i.title).toBe('Open City')
    expect(i.creators).toEqual(['Teju Cole'])
    expect(i.kind).toBe('book')
    expect(i.rating).toBe(5)
    expect(i.owned).toBe(true)
    expect(i.status).toBe('none')
    expect('foo' in i).toBe(false)
    expect(Object.values(i).includes(undefined)).toBe(false)
  })
  it('splits creator strings', () => {
    expect(item({ creators: 'Mary Auld / Elisa Paganelli' }).creators).toEqual(['Mary Auld', 'Elisa Paganelli'])
    expect(item({ creators: 'Abouet & Sapin' }).creators).toEqual(['Abouet', 'Sapin'])
  })
  it('rejects non-image cover data', () => {
    expect(item({ coverData: 'javascript:alert(1)' }).coverData).toBeUndefined()
    expect(item({ coverData: 'data:image/jpeg;base64,AAA' }).coverData).toBe('data:image/jpeg;base64,AAA')
  })
})

describe('search, filter, sort', () => {
  const lib = [
    item({ id: 'a', title: 'Der Koran', creators: ['Goodword'], room: 'Wohnzimmer', shelf: 'oben', rating: 4 }),
    item({ id: 'b', title: 'Kalle Blomquist', creators: ['Astrid Lindgren'], room: 'Kleines Zimmer', status: 'done' }),
    item({ id: 'c', title: 'Sind Dinos tot?', creators: ['Mai Thi Nguyen-Kim'], owned: false }),
    item({ id: 'd', title: 'Ginseng Wurzeln', creators: ['Craig Thompson'], room: 'Wohnzimmer', loans: [{ to: 'Eric', since: '2026-01-02' }] }),
    item({ id: 'e', title: 'Catan', kind: 'game', recommend: true }),
  ]
  it('folds umlauts and case', () => {
    expect(fold('Größe ÄRGER')).toBe('grosse arger')
  })
  it('searches across fields', () => {
    expect(applyFilters(lib, { ...EMPTY_FILTERS, q: 'lindgren kalle' }).map((i) => i.id)).toEqual(['b'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, q: 'wohnzimmer' }).map((i) => i.id)).toEqual(['a', 'd'])
  })
  it('filters by scope', () => {
    expect(applyFilters(lib, { ...EMPTY_FILTERS, scope: 'wish' }).map((i) => i.id)).toEqual(['c'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, scope: 'lent' }).map((i) => i.id)).toEqual(['d'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, scope: 'recommend' }).map((i) => i.id)).toEqual(['e'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, kind: 'game' }).map((i) => i.id)).toEqual(['e'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, room: '' }).map((i) => i.id)).toEqual(['c', 'e'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, minRating: 3 }).map((i) => i.id)).toEqual(['a'])
  })
  it('ignores articles when sorting by title', () => {
    expect(titleKey('Der Koran')).toBe('koran')
    expect(sortItems(lib, 'title', 'de').map((i) => i.id)).toEqual(['e', 'd', 'b', 'a', 'c'])
  })
  it('sorts by surname', () => {
    expect(sortItems(lib, 'creator', 'de')[0].id).toBe('e') // no creator first
    expect(sortItems(lib, 'creator', 'de').map((i) => i.id).slice(1)).toEqual(['a', 'b', 'c', 'd'])
    const hg = [item({ id: 'x', title: 'B', creators: ['Laura Lamping (Hg.)'] }), item({ id: 'y', title: 'A', creators: ['Schami, Rafik'] })]
    expect(sortItems(hg, 'creator', 'de').map((i) => i.id)).toEqual(['x', 'y'])
  })
  it('summarises places of owned physical items', () => {
    const s = summarizePlaces(lib, 'de')
    expect(s.map((r) => [r.room, r.count])).toEqual([
      ['Kleines Zimmer', 1],
      ['Wohnzimmer', 2],
      ['', 1],
    ])
  })
})

describe('duplicates and import', () => {
  const lib = [item({ id: 'a', title: 'Open City', creators: ['Teju Cole'], isbn: '9783518466' }), item({ id: 'b', title: 'Kafka am Strand', creators: ['Haruki Murakami'] })]
  it('finds duplicates by ISBN or title + author', () => {
    expect(findDuplicate(lib, { title: 'anything', isbn: '9783518466' })?.id).toBe('a')
    expect(findDuplicate(lib, { title: 'kafka am strand!', creators: ['Haruki Murakami'] })?.id).toBe('b')
    expect(findDuplicate(lib, { title: 'Kafka am Strand', creators: ['Someone Else'] })).toBeUndefined()
    expect(findDuplicate(lib, { title: 'Kafka am Strand', format: 'ebook' })).toBeUndefined()
    expect(findDuplicate(lib, { title: 'Kafka am Strand' })).toBeUndefined()
    const set = [item({ title: '金瓶梅词话', creators: ['兰陵笑笑生'], volume: '1' })]
    expect(findDuplicate(set, { title: '金瓶梅词话', creators: ['兰陵笑笑生'], volume: '2' })).toBeUndefined()
    expect(findDuplicate(set, { title: '金瓶梅词话', creators: ['兰陵笑笑生'], volume: '1' })).toBeDefined()
  })
  it('round-trips an export', () => {
    const back = parseImport(JSON.stringify(toExport(lib)))
    expect(back).toEqual(lib)
  })
  it('reads the skill import format with a top-level room', () => {
    const list = parseImport(JSON.stringify({ room: 'Küche', items: [{ title: 'Käferkolonne', creators: ['Elise Gravel'] }, { title: 'Freddy', room: 'Wohnzimmer' }, { nope: 1 }] }))
    expect(list.length).toBe(2)
    expect(list[0]).toMatchObject({ room: 'Küche', source: 'import' })
    expect(list[1].room).toBe('Wohnzimmer')
  })
  it('turns old shelves into rooms only where the room says nothing', () => {
    // photo import: room "Foto-Import" + shelf "Foto 4" → room "Foto 4"
    expect(item({ room: 'Foto-Import', shelf: 'Foto 4' }).room).toBe('Foto 4')
    expect(item({ shelf: 'Regal 2' }).room).toBe('Regal 2')
    // a real room wins over a shelf
    expect(item({ room: 'Wohnzimmer', shelf: 'oben' }).room).toBe('Wohnzimmer')
    expect('shelf' in item({ room: 'Wohnzimmer', shelf: 'oben' })).toBe(false)
    const list = parseImport(JSON.stringify({ room: 'Foto-Import', shelf: 'Foto 1', items: [{ title: 'A' }, { title: 'B', shelf: 'Foto 2' }] }))
    expect(list.map((i) => i.room)).toEqual(['Foto 1', 'Foto 2'])
  })
  it('merges: newer wins, duplicates skipped', () => {
    const incoming = [
      { ...lib[0], notes: 'new', updatedAt: '2027-01-01T00:00:00.000Z' },
      item({ title: 'Kafka am Strand', creators: ['Haruki Murakami'] }),
      item({ title: 'Tremolo', creators: ['Tomi Ungerer'] }),
    ]
    const r = mergeItems(lib, incoming)
    expect([r.added, r.updated, r.skipped]).toEqual([1, 1, 1])
    expect(r.items.find((i) => i.id === 'a')?.notes).toBe('new')
  })
  it('exports CSV with escaping', () => {
    const csv = toCSV([item({ title: 'Wurzeln; "Ginseng"', creators: ['A', 'B'] })])
    expect(csv.split('\n')[1]).toContain('"Wurzeln; ""Ginseng"""')
    expect(csv.split('\n')[1]).toContain(';A, B;')
  })
})

describe('recognition helpers', () => {
  it('turns AI results into drafts', () => {
    const d = toDraft({ kind: 'book', title: ' 金瓶梅词话 ', creators: [' 兰陵笑笑生 '], series: '', volume: '3', publisher: '', language: 'zh', confidence: 'medium', remark: 'blurry' })
    expect(d).toMatchObject({ title: '金瓶梅词话', creators: ['兰陵笑笑生'], volume: '3', language: 'zh', needsCheck: true, source: 'ai' })
    expect(d.series).toBeUndefined()
  })
  it('scores online matches', () => {
    const known = { title: 'Open City', creators: ['Teju Cole'] }
    expect(matchScore(known, { via: '', title: 'Open City', subtitle: 'Roman', creators: ['Teju Cole'] })).toBeGreaterThan(0.9)
    expect(matchScore(known, { via: '', title: 'Open City', creators: ['Someone'] })).toBeLessThan(0.75)
    expect(matchScore(known, { via: '', title: 'Closed Town', creators: ['Teju Cole'] })).toBeLessThan(0.75)
  })
})
