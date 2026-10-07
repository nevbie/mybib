import type { ItemDraft, Kind } from '../types'
import { fold } from './items'

/**
 * Online metadata lookup. All services used here allow browser requests (CORS) without a key:
 * - Google Books (optional key raises the shared daily quota, which keyless requests often hit)
 * - Open Library (books, covers)
 * - MusicBrainz + Cover Art Archive (CDs, music DVDs)
 * - UPCitemdb trial endpoint (DVDs / games by barcode, 100 requests per day)
 */

export interface Candidate extends ItemDraft {
  /** which service delivered it, shown in the result list */
  via: string
}

const TIMEOUT = 12000

async function getJson<T>(url: string): Promise<T | null> {
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), TIMEOUT)
  try {
    const res = await fetch(url, { signal: ctl.signal })
    if (!res.ok) return null
    return (await res.json()) as T
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}

/** Resolve true when the URL loads as a real image (Open Library returns 1×1 px for "no cover"). */
export function probeImage(url: string): Promise<boolean> {
  return new Promise((resolve) => {
    const img = new Image()
    const timer = setTimeout(() => resolve(false), TIMEOUT)
    img.onload = () => {
      clearTimeout(timer)
      resolve(img.naturalWidth > 10)
    }
    img.onerror = () => {
      clearTimeout(timer)
      resolve(false)
    }
    img.src = url
  })
}

const year = (s?: string) => {
  const m = s?.match(/\d{4}/)
  return m ? Number(m[0]) : undefined
}

// ---------- Google Books ----------

interface GVolume {
  volumeInfo: {
    title?: string
    subtitle?: string
    authors?: string[]
    publisher?: string
    publishedDate?: string
    description?: string
    pageCount?: number
    language?: string
    industryIdentifiers?: { type: string; identifier: string }[]
    imageLinks?: { thumbnail?: string; smallThumbnail?: string }
  }
}

function fromGoogle(v: GVolume): Candidate | null {
  const i = v.volumeInfo
  if (!i?.title) return null
  const isbn = i.industryIdentifiers?.find((x) => x.type === 'ISBN_13')?.identifier
  const thumb = i.imageLinks?.thumbnail ?? i.imageLinks?.smallThumbnail
  return {
    via: 'Google Books',
    kind: 'book',
    title: i.title,
    subtitle: i.subtitle,
    creators: i.authors ?? [],
    publisher: i.publisher,
    year: year(i.publishedDate),
    description: i.description,
    pages: i.pageCount || undefined,
    language: i.language,
    isbn,
    coverUrl: thumb?.replace(/^http:/, 'https:').replace('&edge=curl', ''),
  }
}

async function google(q: string, key: string, max = 8): Promise<Candidate[]> {
  const url = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&maxResults=${max}&printType=books${key ? `&key=${encodeURIComponent(key)}` : ''}`
  const data = await getJson<{ items?: GVolume[] }>(url)
  return (data?.items ?? []).map(fromGoogle).filter((c): c is Candidate => !!c)
}

// ---------- Open Library ----------

interface OLBook {
  title?: string
  subtitle?: string
  authors?: { name: string }[]
  publishers?: { name: string }[]
  publish_date?: string
  number_of_pages?: number
  cover?: { medium?: string; large?: string }
}

async function openLibraryIsbn(isbn: string): Promise<Candidate | null> {
  const data = await getJson<Record<string, OLBook>>(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`)
  const b = data?.[`ISBN:${isbn}`]
  if (!b?.title) return null
  return {
    via: 'Open Library',
    kind: 'book',
    title: b.title,
    subtitle: b.subtitle,
    creators: b.authors?.map((a) => a.name) ?? [],
    publisher: b.publishers?.[0]?.name,
    year: year(b.publish_date),
    pages: b.number_of_pages,
    isbn,
    coverUrl: b.cover?.medium ?? b.cover?.large,
  }
}

interface OLDoc {
  title?: string
  subtitle?: string
  author_name?: string[]
  first_publish_year?: number
  publisher?: string[]
  isbn?: string[]
  cover_i?: number
  language?: string[]
  number_of_pages_median?: number
}

async function openLibrarySearch(params: string): Promise<Candidate[]> {
  const fields = 'title,subtitle,author_name,first_publish_year,publisher,isbn,cover_i,language,number_of_pages_median'
  const data = await getJson<{ docs?: OLDoc[] }>(`https://openlibrary.org/search.json?${params}&limit=8&fields=${fields}`)
  return (data?.docs ?? [])
    .filter((d) => d.title)
    .map((d) => ({
      via: 'Open Library',
      kind: 'book' as Kind,
      title: d.title!,
      subtitle: d.subtitle,
      creators: d.author_name ?? [],
      year: d.first_publish_year,
      publisher: d.publisher?.[0],
      isbn: d.isbn?.find((x) => x.length === 13 && x.startsWith('97')),
      pages: d.number_of_pages_median,
      language: d.language?.[0],
      coverUrl: d.cover_i ? `https://covers.openlibrary.org/b/id/${d.cover_i}-M.jpg` : undefined,
    }))
}

// ---------- MusicBrainz ----------

interface MBRelease {
  id: string
  title: string
  date?: string
  barcode?: string
  'artist-credit'?: { name: string }[]
  'label-info'?: { label?: { name: string } }[]
  media?: { format?: string }[]
}

function fromMB(r: MBRelease): Candidate {
  const fmt = r.media?.[0]?.format ?? ''
  return {
    via: 'MusicBrainz',
    kind: /dvd|blu-ray/i.test(fmt) ? 'dvd' : 'cd',
    title: r.title,
    creators: r['artist-credit']?.map((a) => a.name) ?? [],
    publisher: r['label-info']?.[0]?.label?.name,
    year: year(r.date),
    isbn: r.barcode || undefined,
    // Cover Art Archive redirects to the image; missing covers are filtered by probeImage later
    coverUrl: `https://coverartarchive.org/release/${r.id}/front-250`,
  }
}

async function musicbrainz(query: string): Promise<Candidate[]> {
  const data = await getJson<{ releases?: MBRelease[] }>(`https://musicbrainz.org/ws/2/release/?query=${encodeURIComponent(query)}&fmt=json&limit=8`)
  return (data?.releases ?? []).map(fromMB)
}

// ---------- UPCitemdb (generic barcodes) ----------

async function upcitemdb(ean: string): Promise<Candidate[]> {
  const data = await getJson<{ items?: { title?: string; brand?: string; category?: string; images?: string[] }[] }>(
    `https://api.upcitemdb.com/prod/trial/lookup?upc=${ean}`,
  )
  return (data?.items ?? [])
    .filter((x) => x.title)
    .map((x) => ({
      via: 'UPCitemdb',
      kind: /game|spiel/i.test(x.category ?? '') ? 'game' : /dvd|blu|movie|film/i.test(x.category ?? '') ? 'dvd' : /music|cd/i.test(x.category ?? '') ? 'cd' : 'dvd',
      title: x.title!,
      creators: [],
      publisher: x.brand,
      isbn: ean,
      coverUrl: x.images?.find((u) => u.startsWith('https:')),
    }))
}

// ---------- public API ----------

/** Fill gaps in `a` with values from `b` (same book from a second service). */
function mergeCandidate(a: Candidate, b: Candidate): Candidate {
  const out: Candidate = { ...a }
  for (const [k, v] of Object.entries(b) as [keyof Candidate, unknown][]) {
    const cur = out[k]
    if (cur === undefined || cur === '' || (Array.isArray(cur) && !cur.length)) (out as unknown as Record<string, unknown>)[k] = v
  }
  out.via = a.via === b.via ? a.via : `${a.via} + ${b.via}`
  return out
}

async function withWorkingCover(c: Candidate): Promise<Candidate> {
  if (c.coverUrl && !(await probeImage(c.coverUrl))) return { ...c, coverUrl: undefined }
  return c
}

/** Look up an ISBN in Google Books and Open Library, merged into one result. */
export async function lookupIsbn(isbn: string, googleKey = ''): Promise<Candidate | null> {
  const [g, ol] = await Promise.all([google(`isbn:${isbn}`, googleKey, 1), openLibraryIsbn(isbn)])
  // Prefer Open Library's cover (larger, no "preview" banner); Google usually has the better text.
  let c: Candidate | null = g[0] ?? null
  if (c && ol) c = mergeCandidate({ ...c, coverUrl: ol.coverUrl ?? c.coverUrl }, ol)
  else c = c ?? ol
  if (!c) return null
  c = { ...c, isbn }
  if (!c.coverUrl) {
    const fallback = `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg?default=false`
    if (await probeImage(fallback)) return { ...c, coverUrl: fallback }
    return c
  }
  return withWorkingCover(c)
}

/** Look up a non-ISBN barcode (CD, DVD, game). */
export async function lookupEan(ean: string): Promise<Candidate[]> {
  const mb = await musicbrainz(`barcode:${ean}`)
  const list = mb.length ? mb : await upcitemdb(ean)
  return Promise.all(list.slice(0, 5).map(withWorkingCover))
}

/** Free-text search by title / creator for the chosen kind. */
export async function searchOnline(kind: Kind, title: string, creator: string, googleKey = ''): Promise<Candidate[]> {
  title = title.trim()
  creator = creator.trim()
  if (!title && !creator) return []
  let list: Candidate[] = []
  if (kind === 'book') {
    const gq = [title && `intitle:${title}`, creator && `inauthor:${creator}`].filter(Boolean).join(' ')
    const olq = [title && `title=${encodeURIComponent(title)}`, creator && `author=${encodeURIComponent(creator)}`].filter(Boolean).join('&')
    const [g, ol] = await Promise.all([google(gq, googleKey), openLibrarySearch(olq)])
    list = dedupe([...g, ...ol])
  } else if (kind === 'cd' || kind === 'dvd') {
    const q = [title && `release:"${title.replace(/"/g, '')}"`, creator && `artist:"${creator.replace(/"/g, '')}"`].filter(Boolean).join(' AND ')
    list = await musicbrainz(q)
    if (kind === 'dvd') list = list.filter((c) => c.kind === 'dvd').concat(list.filter((c) => c.kind !== 'dvd'))
  }
  return Promise.all(list.slice(0, 10).map(withWorkingCover))
}

/** Same title+first author from two services → keep one, merged. */
function dedupe(list: Candidate[]): Candidate[] {
  const out: Candidate[] = []
  for (const c of list) {
    const key = fold(c.title) + '|' + fold(c.creators?.[0] ?? '')
    const i = out.findIndex((o) => fold(o.title) + '|' + fold(o.creators?.[0] ?? '') === key)
    if (i >= 0) out[i] = mergeCandidate(out[i], c)
    else out.push(c)
  }
  return out
}

/**
 * How well does an online result match what we already know (e.g. from a spine photo)?
 * 0…1 – used to auto-enrich AI results only when the match is convincing.
 */
export function matchScore(known: { title: string; creators?: string[] }, c: Candidate): number {
  const words = (s: string) => new Set(fold(s).split(' ').filter((w) => w.length > 1))
  const a = words(known.title)
  const b = words(c.title + ' ' + (c.subtitle ?? ''))
  if (!a.size) return 0
  let hit = 0
  for (const w of a) if (b.has(w)) hit++
  let score = hit / a.size
  const kc = known.creators?.[0]
  if (kc) {
    const last = fold(kc).split(' ').pop() ?? ''
    const has = (c.creators ?? []).some((x) => fold(x).includes(last))
    score = score * 0.7 + (has ? 0.3 : 0)
  }
  return score
}
