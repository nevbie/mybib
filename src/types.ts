export type Lang = 'de' | 'en'

/** What kind of thing sits on the shelf. */
export const KINDS = ['book', 'game', 'dvd', 'cd'] as const
export type Kind = (typeof KINDS)[number]

/** Physical copy, e-book or audiobook (only meaningful for books). */
export const FORMATS = ['physical', 'ebook', 'audio'] as const
export type Format = (typeof FORMATS)[number]

/**
 * Reading (playing, watching, listening) status.
 * `want` = want to read / play / watch, `done` = read / played / watched / heard.
 */
export const STATUSES = ['none', 'want', 'active', 'done'] as const
export type Status = (typeof STATUSES)[number]

/** Where an item came from – useful to find entries that still need checking. */
export type Source = 'manual' | 'isbn' | 'search' | 'ai' | 'import'

export interface Loan {
  to: string
  /** ISO date YYYY-MM-DD */
  since: string
  /** ISO date when it came back; unset while it is still lent out */
  returned?: string
}

export interface Item {
  id: string
  kind: Kind
  title: string
  subtitle?: string
  /** authors, artists, directors or game designers */
  creators: string[]
  publisher?: string
  year?: number
  /** ISBN-13 for books, EAN / UPC for everything else */
  isbn?: string
  language?: string
  series?: string
  volume?: string
  pages?: number
  description?: string
  /** remote cover (Open Library, Google Books, Cover Art Archive) */
  coverUrl?: string
  /** own photo, downscaled JPEG data URL – wins over coverUrl */
  coverData?: string
  tags: string[]

  format: Format
  /** false = wishlist (not owned yet) */
  owned: boolean
  status: Status
  /** 0 = not rated, 1–5 stars */
  rating: number
  recommend: boolean
  notes?: string

  room?: string

  /** board games */
  playersMin?: number
  playersMax?: number
  playMinutes?: number
  /** age recommendation, e.g. kids' books and games */
  ageFrom?: number

  /** all loans, newest last; the open one has no `returned` */
  loans: Loan[]

  /** set by the photo recognition when it is unsure – shown as "please check" */
  needsCheck?: boolean
  /** date of the last automatic online lookup (bulk completion), so it isn't retried every time */
  lookedUp?: string
  source: Source
  addedAt: string
  updatedAt: string
}

export type ItemDraft = Partial<Item> & { title: string }

export interface Settings {
  claudeKey: string
  claudeModel: string
  googleBooksKey: string
  /** last room used when adding, so batch entry stays quick */
  lastRoom: string
  /** rooms shown even when empty; [] = use the default rooms */
  rooms: string[]
}

export const DEFAULT_SETTINGS: Settings = {
  claudeKey: '',
  claudeModel: 'claude-opus-5-5',
  googleBooksKey: '',
  lastRoom: '',
  rooms: [],
}

export const DEFAULT_ROOMS: [string, string][] = [
  ['Küche', 'Kitchen'],
  ['Wohnzimmer', 'Living room'],
  ['Kleines Zimmer', 'Small room'],
]
