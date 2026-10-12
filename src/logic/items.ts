import { toCategory } from './categories'
import { FORMATS, KINDS, STATUSES, type Format, type Item, type ItemDraft, type Kind, type Status } from '../types'

export function newId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

export function today(): string {
  return new Date().toISOString().slice(0, 10)
}

const str = (v: unknown): string | undefined => (typeof v === 'string' && v.trim() ? v.trim() : typeof v === 'number' ? String(v) : undefined)
const num = (v: unknown): number | undefined => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? parseInt(v, 10) : NaN
  return Number.isFinite(n) ? n : undefined
}
const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.map(str).filter((s): s is string => !!s) : typeof v === 'string' && v.trim() ? v.split(/\s*[;/]\s*|\s+&\s+/).filter(Boolean) : []
const oneOf = <T extends string>(list: readonly T[], v: unknown, fallback: T): T => (list.includes(v as T) ? (v as T) : fallback)

/**
 * Only rooms are kept. Older data and imports may still carry a shelf: the photo import put
 * everything in room "Foto-Import" with shelves "Foto 1" … – those shelves become rooms.
 */
function roomOf(r: Record<string, unknown>): string | undefined {
  const room = str(r.room)
  const shelf = str(r.shelf)
  if (shelf && (!room || room === 'Foto-Import')) return shelf
  return room
}

/**
 * Turn anything that looks roughly like an item (form draft, AI result, imported JSON)
 * into a complete, valid Item. Unknown fields are dropped.
 */
export function normalizeItem(d: ItemDraft | Record<string, unknown>, now = new Date().toISOString()): Item {
  const r = d as Record<string, unknown>
  const loans = Array.isArray(r.loans)
    ? (r.loans as Record<string, unknown>[])
        .map((l) => ({ to: str(l.to) ?? '', since: str(l.since) ?? today(), ...(str(l.returned) ? { returned: str(l.returned) } : {}) }))
        .filter((l) => l.to)
    : []
  const rating = Math.max(0, Math.min(5, Math.round(num(r.rating) ?? 0)))
  const item: Item = {
    id: str(r.id) ?? newId(),
    kind: oneOf<Kind>(KINDS, r.kind, 'book'),
    title: str(r.title) ?? '?',
    subtitle: str(r.subtitle),
    creators: strList(r.creators ?? r.authors ?? r.author),
    publisher: str(r.publisher),
    year: num(r.year),
    isbn: str(r.isbn)?.replace(/[^0-9X]/gi, ''),
    language: str(r.language),
    series: str(r.series),
    volume: str(r.volume),
    pages: num(r.pages),
    description: str(r.description),
    coverUrl: str(r.coverUrl),
    coverData: typeof r.coverData === 'string' && r.coverData.startsWith('data:image/') ? r.coverData : undefined,
    tags: strList(r.tags),
    category: toCategory(str(r.category)),
    format: oneOf<Format>(FORMATS, r.format, 'physical'),
    owned: r.owned !== false,
    status: oneOf<Status>(STATUSES, r.status, 'none'),
    rating,
    recommend: r.recommend === true,
    notes: str(r.notes),
    room: roomOf(r),
    playersMin: num(r.playersMin),
    playersMax: num(r.playersMax),
    playMinutes: num(r.playMinutes),
    ageFrom: num(r.ageFrom),
    loans,
    needsCheck: r.needsCheck === true ? true : undefined,
    lookedUp: str(r.lookedUp),
    source: oneOf(['manual', 'isbn', 'search', 'ai', 'import'] as const, r.source, 'manual'),
    addedAt: str(r.addedAt) ?? now,
    updatedAt: str(r.updatedAt) ?? now,
  }
  // drop undefined keys so stored objects and exports stay tidy
  for (const k of Object.keys(item) as (keyof Item)[]) if (item[k] === undefined) delete item[k]
  return item
}

export function openLoan(item: Item) {
  return item.loans.find((l) => !l.returned)
}

/** Lower-case, strip accents and punctuation – for search and duplicate detection. */
export function fold(s: string): string {
  return s
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/ß/g, 'ss')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** Probable duplicate already in the catalogue (same ISBN, or same title + first creator). */
export function findDuplicate(items: Item[], d: { isbn?: string; title: string; creators?: string[]; volume?: string; kind?: Kind; format?: Format }): Item | undefined {
  if (d.isbn) {
    const hit = items.find((i) => i.isbn === d.isbn)
    if (hit) return hit
  }
  const t = fold(d.title)
  const c = d.creators?.[0] ? fold(d.creators[0]) : ''
  const v = d.volume ? fold(d.volume) : ''
  if (!t) return undefined
  // same title, same first creator (or both unknown), same volume – volumes of a set are not duplicates
  return items.find(
    (i) =>
      fold(i.title) === t &&
      (i.creators[0] ? fold(i.creators[0]) : '') === c &&
      (i.volume ? fold(i.volume) : '') === v &&
      (!d.kind || i.kind === d.kind) &&
      (!d.format || i.format === d.format),
  )
}

export interface Filters {
  q: string
  /** 'book' = printed (and audio) books, 'ebook' = e-books */
  kind: Kind | 'all' | 'ebook'
  status: Status | 'all'
  /** owned / wishlist / lent / recommended / to check */
  scope: 'all' | 'owned' | 'wish' | 'lent' | 'recommend' | 'check'
  format: Format | 'all'
  room: string | 'all'
  /** category id/name, '' = without category */
  category: string | 'all'
  /** language code, '' = without language */
  language: string | 'all'
  minRating: number
}

export const EMPTY_FILTERS: Filters = { q: '', kind: 'all', status: 'all', scope: 'all', format: 'all', room: 'all', category: 'all', language: 'all', minRating: 0 }

export type SortKey = 'title' | 'creator' | 'added' | 'rating' | 'year' | 'place'

export function searchText(i: Item): string {
  return fold([i.title, i.subtitle, ...i.creators, i.series, i.publisher, i.isbn, i.notes, ...i.tags, i.room].filter(Boolean).join(' '))
}

export function applyFilters(items: Item[], f: Filters): Item[] {
  const words = fold(f.q).split(' ').filter(Boolean)
  return items.filter((i) => {
    if (f.kind === 'ebook') {
      if (i.format !== 'ebook') return false
    } else if (f.kind !== 'all' && (i.kind !== f.kind || (f.kind === 'book' && i.format === 'ebook'))) return false
    if (f.language !== undefined && f.language !== 'all' && (i.language ?? '').toLowerCase() !== f.language.toLowerCase()) return false
    if (f.status !== 'all' && i.status !== f.status) return false
    if (f.format !== 'all' && i.format !== f.format) return false
    if (f.room !== 'all' && (i.room ?? '') !== f.room) return false
    if (f.category !== 'all' && (i.category ?? '') !== f.category) return false
    if (f.minRating && i.rating < f.minRating) return false
    switch (f.scope) {
      case 'owned':
        if (!i.owned) return false
        break
      case 'wish':
        if (i.owned) return false
        break
      case 'lent':
        if (!openLoan(i)) return false
        break
      case 'recommend':
        if (!i.recommend) return false
        break
      case 'check':
        if (!i.needsCheck) return false
        break
    }
    if (words.length) {
      const hay = searchText(i)
      if (!words.every((w) => hay.includes(w))) return false
    }
    return true
  })
}

/** Sort key for titles: ignore leading articles so "Der Koran" sorts under K. */
const ARTICLES = /^(der|die|das|ein|eine|the|a|an|le|la|les|el|los|las)\s+/i
export function titleKey(t: string): string {
  return fold(t.replace(ARTICLES, ''))
}

/** Surname-ish key: last word of the first creator. */
export function creatorKey(i: Item): string {
  // "Mai Thi Nguyen-Kim" → "nguyen kim", "Laura Lamping (Hg.)" → "lamping", "Schami, Rafik" → "schami"
  const c = (i.creators[0] ?? '').replace(/\([^)]*\)/g, '').trim()
  const surname = c.includes(',') ? c.split(',')[0] : (c.split(/\s+/).pop() ?? '')
  return fold(surname) + ' ' + titleKey(i.title)
}

export function sortItems(items: Item[], key: SortKey, lang: string): Item[] {
  const coll = new Intl.Collator(lang, { numeric: true })
  const arr = [...items]
  switch (key) {
    case 'title':
      return arr.sort((a, b) => coll.compare(titleKey(a.title), titleKey(b.title)) || coll.compare(a.volume ?? '', b.volume ?? ''))
    case 'creator':
      return arr.sort((a, b) => coll.compare(creatorKey(a), creatorKey(b)))
    case 'added':
      return arr.sort((a, b) => b.addedAt.localeCompare(a.addedAt))
    case 'rating':
      return arr.sort((a, b) => b.rating - a.rating || coll.compare(titleKey(a.title), titleKey(b.title)))
    case 'year':
      return arr.sort((a, b) => (b.year ?? 0) - (a.year ?? 0))
    case 'place':
      return arr.sort((a, b) => coll.compare(a.room ?? '￿', b.room ?? '￿') || coll.compare(titleKey(a.title), titleKey(b.title)))
  }
}

export interface PlaceSummary {
  room: string
  count: number
}

/** Rooms with their item counts ('' = not set); only owned physical items have a place. */
export function summarizePlaces(items: Item[], lang: string): PlaceSummary[] {
  const map = new Map<string, number>()
  for (const i of items) {
    if (!i.owned || i.format !== 'physical') continue
    map.set(i.room ?? '', (map.get(i.room ?? '') ?? 0) + 1)
  }
  const coll = new Intl.Collator(lang, { numeric: true })
  return [...map.entries()].map(([room, count]) => ({ room, count })).sort((a, b) => (a.room ? (b.room ? coll.compare(a.room, b.room) : -1) : 1))
}

// ---------- import / export ----------

export interface ExportFile {
  app: 'mybib'
  version: 1
  exportedAt: string
  items: Item[]
  /** ids deleted or merged away here, so importing elsewhere removes them too */
  removed?: string[]
}

export function toExport(items: Item[], removed: string[] = []): ExportFile {
  return { app: 'mybib', version: 1, exportedAt: new Date().toISOString(), items, ...(removed.length ? { removed } : {}) }
}

/**
 * Read an import file. Accepts a mybib export, a bare array of items, or `{ items: [...] }`
 * (the format the Claude skill produces). A room given at the top level applies to all items
 * that don't have their own.
 */
export function parseImport(text: string): Item[] {
  return parseImportFile(text).items
}

/**
 * Like parseImport, plus the file's mode: `"updateOnly": true` (e.g. a category update made by
 * Claude) only completes books that are already in the catalogue and never adds new ones.
 */
export function parseImportFile(text: string): { items: Item[]; updateOnly: boolean; removed: string[] } {
  const data = JSON.parse(text) as unknown
  const list: unknown[] = Array.isArray(data) ? data : Array.isArray((data as { items?: unknown }).items) ? (data as { items: unknown[] }).items : []
  const removedRaw = Array.isArray(data) ? [] : (data as { removed?: unknown }).removed
  const removed = Array.isArray(removedRaw) ? removedRaw.filter((x): x is string => typeof x === 'string') : []
  if (!list.length && !removed.length) throw new Error('no items')
  const top = Array.isArray(data) ? {} : (data as Record<string, unknown>)
  const isExport = top.app === 'mybib'
  const items = list
    .filter((x): x is Record<string, unknown> => !!x && typeof x === 'object' && typeof (x as { title?: unknown }).title === 'string')
    .map((x) =>
      normalizeItem({
        ...x,
        room: x.room ?? top.room,
        shelf: x.shelf ?? (x.room ? undefined : top.shelf),
        source: isExport ? x.source : 'import',
      }),
    )
  return { items, updateOnly: top.updateOnly === true, removed }
}

/** Fields a later import may fill in when the book is already there but they are still empty. */
const FILLABLE = ['subtitle', 'publisher', 'year', 'isbn', 'language', 'series', 'volume', 'pages', 'description', 'coverUrl', 'category', 'room', 'ageFrom', 'needsCheck'] as const

/** Copy of `old` with its empty fields filled from `inc`, or null when nothing changes. */
export function fillEmpty(old: Item, inc: Item): Item | null {
  const next: Item = { ...old }
  let changed = false
  for (const k of FILLABLE) {
    if ((old[k] === undefined || old[k] === '') && inc[k] !== undefined && inc[k] !== '') {
      ;(next as unknown as Record<string, unknown>)[k] = inc[k]
      changed = true
    }
  }
  if (!old.tags.length && inc.tags.length) {
    next.tags = inc.tags
    changed = true
  }
  return changed ? { ...next, updatedAt: new Date().toISOString() } : null
}

/**
 * Merge imported items: same id → newer `updatedAt` wins; no id match but obvious duplicate
 * (same ISBN or same title/creator/volume/kind/format) → its empty fields are filled in;
 * otherwise added (unless `updateOnly`). Entries deleted or merged away – here (`removedHere`) or on the
 * device the file comes from (`removedThere`) – are never brought back; the latter are deleted here too.
 */
export function mergeItems(
  existing: Item[],
  incoming: Item[],
  updateOnly = false,
  removedHere: Iterable<string> = [],
  removedThere: Iterable<string> = [],
): { items: Item[]; added: number; updated: number; skipped: number; removed: number } {
  const gone = new Set([...removedHere, ...removedThere])
  const dropThere = new Set(removedThere)
  const kept = existing.filter((i) => !dropThere.has(i.id))
  const removed = existing.length - kept.length
  const byId = new Map(kept.map((i) => [i.id, i]))
  let added = 0
  let updated = 0
  let skipped = 0
  const all = [...kept]
  for (const inc of incoming) {
    if (gone.has(inc.id)) {
      skipped++
      continue
    }
    const old = byId.get(inc.id)
    if (old) {
      if (inc.updatedAt > old.updatedAt) {
        all[all.indexOf(old)] = inc
        byId.set(inc.id, inc)
        updated++
      } else skipped++
      continue
    }
    const dup = findDuplicate(all, inc)
    if (dup) {
      const filled = fillEmpty(dup, inc)
      if (filled) {
        all[all.indexOf(dup)] = filled
        byId.set(filled.id, filled)
        updated++
      } else skipped++
      continue
    }
    if (updateOnly) {
      skipped++
      continue
    }
    all.push(inc)
    byId.set(inc.id, inc)
    added++
  }
  return { items: all, added, updated, skipped, removed }
}

const CSV_COLUMNS: (keyof Item | 'lentTo')[] = [
  'kind', 'title', 'subtitle', 'creators', 'publisher', 'year', 'isbn', 'language', 'series', 'volume',
  'format', 'owned', 'status', 'rating', 'recommend', 'category', 'room', 'lentTo', 'tags', 'notes', 'addedAt',
]

/** Spreadsheet-friendly export (semicolon separated, as Excel in German locale expects). */
export function toCSV(items: Item[]): string {
  const esc = (v: unknown) => {
    const s = v === undefined || v === null ? '' : Array.isArray(v) ? v.join(', ') : String(v)
    return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const rows = items.map((i) => CSV_COLUMNS.map((c) => esc(c === 'lentTo' ? openLoan(i)?.to : i[c])).join(';'))
  return '﻿' + [CSV_COLUMNS.join(';'), ...rows].join('\n')
}

/** Rooms to offer: the configured ones (or defaults) plus any used by items. */
export function allRooms(items: Item[], configured: string[], defaults: string[]): string[] {
  const set = new Set(configured.length ? configured : defaults)
  for (const i of items) if (i.room) set.add(i.room)
  return [...set]
}

/** Names used in earlier loans, most recent first. */
export function knownPeople(items: Item[]): string[] {
  const loans = items.flatMap((i) => i.loans).sort((a, b) => b.since.localeCompare(a.since))
  return [...new Set(loans.map((l) => l.to))]
}

/** Stable key of a duplicate group, so "not duplicates" can be remembered (changes when the group changes). */
export function groupKey(items: Item[]): string {
  return items.map((i) => i.id).sort().join(',')
}

/**
 * Groups of probable duplicates: same ISBN, or same title, kind and format where author and volume match
 * or are missing on one side (e.g. the same book entered once with and once without author).
 * Groups marked "not duplicates" (`ignored` keys) are left out.
 */
export function duplicateGroups(items: Item[], ignored: string[] = []): Item[][] {
  const parent = items.map((_, n) => n)
  const root = (n: number): number => (parent[n] === n ? n : (parent[n] = root(parent[n])))
  const join = (a: number, b: number) => {
    parent[root(a)] = root(b)
  }
  const byIsbn = new Map<string, number>()
  const byTitle = new Map<string, number[]>()
  items.forEach((i, n) => {
    if (i.isbn) {
      const m = byIsbn.get(i.isbn)
      if (m === undefined) byIsbn.set(i.isbn, n)
      else join(n, m)
    }
    const t = fold(i.title)
    if (t) {
      const k = [t, i.kind, i.format].join('\u0001')
      byTitle.set(k, [...(byTitle.get(k) ?? []), n])
    }
  })
  const fits = (a: string, b: string) => a === b || !a || !b
  for (const list of byTitle.values()) {
    for (let x = 0; x < list.length; x++) {
      for (let y = x + 1; y < list.length; y++) {
        const [i, j] = [items[list[x]], items[list[y]]]
        if (fits(i.creators[0] ? fold(i.creators[0]) : '', j.creators[0] ? fold(j.creators[0]) : '') && fits(i.volume ? fold(i.volume) : '', j.volume ? fold(j.volume) : ''))
          join(list[x], list[y])
      }
    }
  }
  const groups = new Map<number, Item[]>()
  items.forEach((i, n) => {
    const r = root(n)
    groups.set(r, [...(groups.get(r) ?? []), i])
  })
  const skip = new Set(ignored)
  return [...groups.values()].filter((g) => g.length > 1 && !skip.has(groupKey(g)))
}

const STATUS_RANK = { none: 0, want: 1, active: 2, done: 3 } as const

/** How much is filled in – the most complete entry of a group is kept when merging. */
function completeness(i: Item): number {
  const vals = [i.subtitle, i.publisher, i.year, i.isbn, i.language, i.series, i.volume, i.pages, i.description, i.coverUrl, i.coverData, i.category, i.room, i.notes]
  return vals.filter((v) => v !== undefined && v !== '').length + i.creators.length + i.tags.length + i.loans.length + (i.rating ? 1 : 0)
}

/**
 * Merge a duplicate group into one entry: keeps the most complete (on a tie the oldest) entry, fills its empty
 * fields from the others, and combines what is personal – best rating, furthest status, recommendation,
 * owned, notes, tags, loans. Returns the merged entry and the ids to delete.
 */
export function mergeGroup(group: Item[]): { keep: Item; remove: string[] } {
  const sorted = [...group].sort((a, b) => completeness(b) - completeness(a) || a.addedAt.localeCompare(b.addedAt))
  let keep: Item = { ...sorted[0] }
  for (const other of sorted.slice(1)) keep = fillEmpty(keep, other) ?? keep
  const all = sorted
  keep.coverData ??= all.find((i) => i.coverData)?.coverData
  if (!keep.creators.length) keep.creators = all.find((i) => i.creators.length)?.creators ?? []
  keep.rating = Math.max(...all.map((i) => i.rating))
  keep.status = all.map((i) => i.status).reduce((a, b) => (STATUS_RANK[b] > STATUS_RANK[a] ? b : a))
  keep.recommend = all.some((i) => i.recommend)
  keep.owned = all.some((i) => i.owned)
  keep.tags = [...new Set(all.flatMap((i) => i.tags))]
  const notes = [...new Set(all.map((i) => i.notes?.trim()).filter((n): n is string => !!n))]
  keep.notes = notes.length ? notes.join('\n\n') : undefined
  const loans = new Map(all.flatMap((i) => i.loans).map((l) => [`${l.to}\u0001${l.since}`, l]))
  keep.loans = [...loans.values()].sort((a, b) => a.since.localeCompare(b.since))
  keep.addedAt = all.map((i) => i.addedAt).sort()[0]
  return { keep, remove: sorted.slice(1).map((i) => i.id) }
}

/**
 * Existing entry a newly recognised item probably is: same ISBN, or same title and kind where author and
 * volume match or are missing on one side (looser than `findDuplicate`, for adding covers to what is there).
 */
export function findMatch(items: Item[], d: { isbn?: string; title: string; creators?: string[]; volume?: string; kind?: Kind }): Item | undefined {
  if (d.isbn) {
    const hit = items.find((i) => i.isbn === d.isbn)
    if (hit) return hit
  }
  const t = fold(d.title)
  if (!t) return undefined
  const c = d.creators?.[0] ? fold(d.creators[0]) : ''
  const v = d.volume ? fold(d.volume) : ''
  const fits = (a: string, b: string) => a === b || !a || !b
  const hits = items.filter(
    (i) => fold(i.title) === t && (!d.kind || i.kind === d.kind) && fits(i.creators[0] ? fold(i.creators[0]) : '', c) && fits(i.volume ? fold(i.volume) : '', v),
  )
  // a printed copy is the one a cover photo belongs to
  return hits.find((i) => i.format === 'physical') ?? hits[0]
}

/** What a recognised item adds to an existing entry: its empty fields, the creators if none, own cover photo if none. */
export function completionPatch(old: Item, d: ItemDraft): Partial<Item> {
  const patch: Partial<Item> = {}
  for (const k of FILLABLE) {
    if (k === 'needsCheck' || k === 'room') continue
    const v = (d as Record<string, unknown>)[k]
    if ((old[k] === undefined || old[k] === '') && v !== undefined && v !== '') (patch as Record<string, unknown>)[k] = v
  }
  if (!old.creators.length && d.creators?.length) patch.creators = d.creators
  if (!old.coverData && d.coverData) patch.coverData = d.coverData
  return patch
}

/** Fields offered for choice when merging by hand (cover = own photo and online cover together). */
export const MERGE_FIELDS = ['cover', 'title', 'subtitle', 'creators', 'series', 'volume', 'publisher', 'year', 'isbn', 'language', 'pages', 'kind', 'format', 'category', 'room', 'description', 'status', 'rating'] as const
export type MergeField = (typeof MERGE_FIELDS)[number]

/** Value of a merge field, for comparing and showing; '' when empty. */
export function mergeValue(i: Item, f: MergeField): string {
  if (f === 'cover') return i.coverData ?? i.coverUrl ?? ''
  if (f === 'creators') return i.creators.join(', ')
  if (f === 'rating') return i.rating ? String(i.rating) : ''
  if (f === 'status') return i.status === 'none' ? '' : i.status
  const v = i[f]
  return v === undefined || v === null ? '' : String(v)
}

/** Fields where the entries of a group differ (and at least one has a value) – the ones worth a choice. */
export function differingFields(group: Item[]): MergeField[] {
  return MERGE_FIELDS.filter((f) => {
    const vals = new Set(group.map((i) => mergeValue(i, f)))
    return vals.size > 1
  })
}

/**
 * Merge with the owner's choices: `choices` maps a field to the id of the entry whose value wins.
 * Everything not chosen comes from `mergeGroup` (most complete entry, gaps filled, notes/tags/loans combined).
 */
export function mergeWithChoices(group: Item[], choices: Partial<Record<MergeField, string>>): { keep: Item; remove: string[] } {
  const base = mergeGroup(group)
  const keep: Item = { ...base.keep }
  for (const [f, id] of Object.entries(choices) as [MergeField, string][]) {
    const src = group.find((i) => i.id === id)
    if (!src) continue
    if (f === 'cover') {
      keep.coverData = src.coverData
      keep.coverUrl = src.coverUrl
    } else (keep as unknown as Record<string, unknown>)[f] = (src as unknown as Record<string, unknown>)[f]
  }
  return { keep, remove: base.remove }
}

/**
 * Similar entries: same title and kind, but author, volume or format differ (e.g. two volumes, or one
 * entry with a typo in the author). Not duplicates for sure – shown separately so they can be merged by hand.
 */
export function similarGroups(items: Item[], ignored: string[] = [], exclude: Set<string> = new Set()): Item[][] {
  const byTitle = new Map<string, Item[]>()
  for (const i of items) {
    if (exclude.has(i.id)) continue
    const t = fold(i.title)
    if (!t) continue
    const k = `${t}\u0001${i.kind}`
    byTitle.set(k, [...(byTitle.get(k) ?? []), i])
  }
  const skip = new Set(ignored)
  return [...byTitle.values()].filter((g) => g.length > 1 && !skip.has(groupKey(g)))
}

/** Language codes used in the catalogue, sorted. */
export function allLanguages(items: Item[]): string[] {
  return [...new Set(items.map((i) => i.language?.toLowerCase()).filter((l): l is string => !!l))].sort()
}
