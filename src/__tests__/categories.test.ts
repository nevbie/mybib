import { describe, expect, it } from 'vitest'
import { allCategories, categoryLabel, DEFAULT_CATEGORY_IDS, toCategory } from '../logic/categories'
import { applyFilters, EMPTY_FILTERS, mergeItems, normalizeItem, parseImportFile } from '../logic/items'

const item = (p: Record<string, unknown>) => normalizeItem({ title: 'x', ...p } as never)

describe('categories', () => {
  it('has 17 defaults with both languages', () => {
    expect(DEFAULT_CATEGORY_IDS.length).toBe(17)
    expect(categoryLabel('youth', 'de')).toBe('Jugendbuch')
    expect(categoryLabel('youth', 'en')).toBe('Young adult')
    expect(categoryLabel('Gleitschirm', 'en')).toBe('Gleitschirm')
  })
  it('maps names to ids', () => {
    expect(toCategory('Sachbuch')).toBe('nonfiction')
    expect(toCategory('krimi & thriller')).toBe('crime')
    expect(toCategory('Picture book')).toBe('picture')
    expect(toCategory('comic')).toBe('comic')
    expect(toCategory('Gleitschirm')).toBe('Gleitschirm')
    expect(toCategory('  ')).toBeUndefined()
    expect(item({ category: 'Kinderbuch' }).category).toBe('children')
  })
  it('lists configured, else default, plus used ones', () => {
    expect(allCategories([], ['Gleitschirm', undefined]).slice(-1)).toEqual(['Gleitschirm'])
    expect(allCategories(['novel', 'crime'], ['youth'])).toEqual(['novel', 'crime', 'youth'])
  })
  it('filters by category, "" = without', () => {
    const lib = [item({ id: 'a', category: 'youth' }), item({ id: 'b' })]
    expect(applyFilters(lib, { ...EMPTY_FILTERS, category: 'youth' }).map((i) => i.id)).toEqual(['a'])
    expect(applyFilters(lib, { ...EMPTY_FILTERS, category: '' }).map((i) => i.id)).toEqual(['b'])
  })
})

describe('update-only import', () => {
  const lib = [
    item({ id: 'a', title: 'Kalle Blomquist', creators: ['Astrid Lindgren'], room: 'Wohnzimmer' }),
    item({ id: 'b', title: 'Hannibal', creators: ['Thomas Harris'], category: 'novel' }),
  ]
  const file = JSON.stringify({
    updateOnly: true,
    items: [
      { title: 'Kalle Blomquist', creators: ['Astrid Lindgren'], category: 'Kinderbuch' },
      { title: 'Hannibal', creators: ['Thomas Harris'], category: 'Krimi & Thriller' },
      { title: 'Not in the catalogue', category: 'Humor' },
    ],
  })
  it('fills empty fields only and adds nothing', () => {
    const { items, updateOnly } = parseImportFile(file)
    expect(updateOnly).toBe(true)
    const r = mergeItems(lib, items, updateOnly)
    expect([r.added, r.updated, r.skipped]).toEqual([0, 1, 2])
    expect(r.items.find((i) => i.id === 'a')).toMatchObject({ category: 'children', room: 'Wohnzimmer' })
    // an existing category is never overwritten
    expect(r.items.find((i) => i.id === 'b')?.category).toBe('novel')
    expect(r.items.length).toBe(2)
  })
  it('normal imports also complete duplicates instead of skipping them', () => {
    const r = mergeItems(lib, [item({ title: 'Kalle Blomquist', creators: ['Astrid Lindgren'], year: 1946 })])
    expect([r.added, r.updated]).toEqual([0, 1])
    expect(r.items.find((i) => i.id === 'a')?.year).toBe(1946)
  })
})
