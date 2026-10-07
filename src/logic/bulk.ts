import type { Item } from '../types'

export type InfoField = 'cover' | 'publisher' | 'year' | 'isbn' | 'description'

/** Which of the details that online sources can deliver are still missing. */
export function missingInfo(i: Item): InfoField[] {
  const out: InfoField[] = []
  if (!i.coverUrl && !i.coverData) out.push('cover')
  if (!i.publisher) out.push('publisher')
  if (!i.year) out.push('year')
  if (!i.isbn) out.push('isbn')
  if (!i.description) out.push('description')
  return out
}

/** Books that could still gain details; `retry` includes those already looked up without success. */
export function bulkTargets(items: Item[], retry: boolean): Item[] {
  return items.filter((i) => i.kind === 'book' && missingInfo(i).length > 0 && (retry || !i.lookedUp))
}
