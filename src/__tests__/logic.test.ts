import { describe, expect, it } from 'vitest'
import { classifyCode, isbn10to13, isValidEan13, isValidIsbn10 } from '../logic/isbn'
import { applyFilters, completionPatch, differingFields, duplicateGroups, mergeWithChoices, similarGroups, EMPTY_FILTERS, findDuplicate, findMatch, groupKey, mergeGroup, fold, mergeItems, normalizeItem, parseImport, parseImportFile, sortItems, summarizePlaces, titleKey, toCSV, toExport } from '../logic/items'
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

describe('duplicates', () => {
  const mk = (d: Record<string, unknown>) => normalizeItem({ title: 'x', ...d })
  it('groups by ISBN and by title/creator/volume/kind/format', () => {
    const a = mk({ id: 'a', title: 'Momo', creators: ['Michael Ende'], isbn: '9783522202107' })
    const b = mk({ id: 'b', title: 'momo', creators: ['Michael Ende'] })
    const c = mk({ id: 'c', title: 'Anderes Buch', isbn: '9783522202107' })
    const d = mk({ id: 'd', title: 'Momo', creators: ['Michael Ende'], format: 'ebook' })
    const e = mk({ id: 'e', title: 'Sahara', creators: ['A'] })
    const f = mk({ id: 'f', title: 'Sahara', creators: ['B'] })
    const g1 = mk({ id: 'g1', title: 'Der Papyrus des Cäsar', creators: ['Jean-Yves Ferri'], volume: '36' })
    const g2 = mk({ id: 'g2', title: 'Der Papyrus des Cäsar', volume: '36' })
    const h1 = mk({ id: 'h1', title: 'Asterix', volume: '1' })
    const h2 = mk({ id: 'h2', title: 'Asterix', volume: '2' })
    const groups = duplicateGroups([a, b, c, d, e, f, g1, g2, h1, h2])
    expect(groups.map((g) => g.map((i) => i.id).sort())).toEqual([['a', 'b', 'c'], ['g1', 'g2']])
    expect(duplicateGroups([a, b, c, d], [groupKey(groups[0])])).toEqual([])
  })

  it('merges into the most complete entry and combines personal data', () => {
    const a = mk({ id: 'a', title: 'Momo', creators: ['Michael Ende'], rating: 2, status: 'want', notes: 'Geschenk', addedAt: '2026-01-02', loans: [{ to: 'Anna', since: '2026-02-01', returned: '2026-03-01' }] })
    const b = mk({ id: 'b', title: 'Momo', creators: ['Michael Ende'], publisher: 'Thienemann', year: 1973, isbn: '9783522202107', coverUrl: 'http://c', rating: 5, status: 'done', tags: ['Kinder'], addedAt: '2026-01-05', owned: false })
    const { keep, remove } = mergeGroup([a, b])
    expect(keep.id).toBe('b')
    expect(remove).toEqual(['a'])
    expect(keep).toMatchObject({ publisher: 'Thienemann', rating: 5, status: 'done', notes: 'Geschenk', owned: true, addedAt: '2026-01-02', tags: ['Kinder'] })
    expect(keep.loans).toHaveLength(1)
  })
})

describe('cover photos for existing entries', () => {
  const mk = (d: Record<string, unknown>) => normalizeItem({ title: 'x', ...d })
  const items = [
    mk({ id: 'a', title: '100 Kinder', creators: ['Christoph Drösser'], room: 'Wohnzimmer', rating: 4 }),
    mk({ id: 'b', title: 'Sterne', kind: 'book', format: 'ebook' }),
    mk({ id: 'c', title: 'Sterne', kind: 'book', coverData: 'data:image/jpeg;base64,old' }),
  ]
  it('finds the existing entry even when the author is missing on one side', () => {
    expect(findMatch(items, { title: '100 Kinder', creators: [], kind: 'book' })?.id).toBe('a')
    expect(findMatch(items, { title: '100 Kinder', creators: ['Nora Coenenberg'], kind: 'book' })).toBeUndefined()
    expect(findMatch(items, { title: 'Sterne', kind: 'book' })?.id).toBe('c')
    expect(findMatch(items, { title: 'Freundschaft', kind: 'book' })).toBeUndefined()
  })
  it('only fills what is missing', () => {
    const p = completionPatch(items[0], { title: '100 Kinder', creators: ['X'], publisher: 'Gabriel', coverData: 'data:image/jpeg;base64,new', room: 'Küche' })
    expect(p).toEqual({ publisher: 'Gabriel', coverData: 'data:image/jpeg;base64,new' })
    expect(completionPatch(items[2], { title: 'Sterne', coverData: 'data:image/jpeg;base64,new' })).toEqual({})
  })
})

describe('merging by hand', () => {
  const mk = (d: Record<string, unknown>) => normalizeItem({ title: 'x', ...d })
  const a = mk({ id: 'a', title: 'Western Circus', volume: '22', creators: ['Morris', 'Goscinny'], coverData: 'data:image/jpeg;base64,A', addedAt: '2026-01-01' })
  const b = mk({ id: 'b', title: 'Western Circus', volume: '62', creators: ['Morris', 'René Goscinny'], room: 'Wohnzimmer', coverData: 'data:image/jpeg;base64,B', rating: 3, addedAt: '2026-01-02' })
  it('lists the differing fields and finds similar entries', () => {
    expect(differingFields([a, b])).toEqual(['cover', 'creators', 'volume', 'room', 'rating'])
    expect(similarGroups([a, b, mk({ id: 'c', title: 'Other' })]).map((g) => g.map((i) => i.id))).toEqual([['a', 'b']])
    expect(similarGroups([a, b], [], new Set(['a']))).toEqual([])
  })
  it('takes the chosen values', () => {
    const { keep, remove } = mergeWithChoices([a, b], { cover: 'a', volume: 'b', creators: 'a' })
    expect(keep.id).toBe('b')
    expect(remove).toEqual(['a'])
    expect(keep).toMatchObject({ coverData: 'data:image/jpeg;base64,A', volume: '62', creators: ['Morris', 'Goscinny'], room: 'Wohnzimmer', rating: 3 })
  })
})

describe('deleted and merged entries stay gone', () => {
  const mk = (d: Record<string, unknown>) => normalizeItem({ title: 'x', ...d })
  const a = mk({ id: 'a', title: 'Western Circus', volume: '22' })
  const b = mk({ id: 'b', title: 'Western Circus', volume: '62' })
  const c = mk({ id: 'c', title: 'Momo' })
  it('does not bring back entries removed here', () => {
    const r = mergeItems([b, c], [a, b, c], false, ['a'])
    expect(r.items.map((i) => i.id)).toEqual(['b', 'c'])
    expect(r.added).toBe(0)
  })
  it('removes entries the file says were removed elsewhere', () => {
    const r = mergeItems([a, b, c], [b, c], false, [], ['a'])
    expect(r.items.map((i) => i.id)).toEqual(['b', 'c'])
    expect(r.removed).toBe(1)
  })
  it('writes and reads the removed list', () => {
    const file = JSON.stringify(toExport([b], ['a']))
    expect(parseImportFile(file).removed).toEqual(['a'])
    expect(parseImportFile(JSON.stringify(toExport([b]))).removed).toEqual([])
  })
})
