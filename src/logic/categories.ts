import type { Lang } from '../types'

/** Default categories: id → [German, English]. Grouped for the picker. */
export const DEFAULT_CATEGORIES: { group: [string, string]; items: [string, string, string][] }[] = [
  {
    group: ['Kinder & Jugend', 'Children & young adults'],
    items: [
      ['picture', 'Bilderbuch', 'Picture book'],
      ['children', 'Kinderbuch', "Children's book"],
      ['youth', 'Jugendbuch', 'Young adult'],
      ['comic', 'Comic & Graphic Novel', 'Comics & graphic novels'],
    ],
  },
  {
    group: ['Belletristik', 'Fiction'],
    items: [
      ['novel', 'Roman & Erzählung', 'Novels & stories'],
      ['crime', 'Krimi & Thriller', 'Crime & thriller'],
      ['fantasy', 'Fantasy & Science-Fiction', 'Fantasy & science fiction'],
      ['classic', 'Klassiker, Drama & Lyrik', 'Classics, drama & poetry'],
      ['humor', 'Humor', 'Humour'],
    ],
  },
  {
    group: ['Sachbuch', 'Non-fiction'],
    items: [
      ['nonfiction', 'Sachbuch', 'Non-fiction'],
      ['guide', 'Ratgeber', 'Self-help & advice'],
      ['cooking', 'Kochen & Trinken', 'Food & drink'],
      ['travel', 'Reise & Sprachführer', 'Travel & phrasebooks'],
      ['hobby', 'Sport, Outdoor & Hobby', 'Sport, outdoors & hobbies'],
      ['arts', 'Kunst, Musik & Design', 'Art, music & design'],
      ['religion', 'Religion & Philosophie', 'Religion & philosophy'],
      ['reference', 'Wörterbuch & Lernen', 'Dictionaries & learning'],
    ],
  },
]

const BY_ID = new Map(DEFAULT_CATEGORIES.flatMap((g) => g.items.map(([id, de, en]) => [id, [de, en] as const])))
export const DEFAULT_CATEGORY_IDS = [...BY_ID.keys()]

/** Display name: default categories are translated, own categories are shown as typed. */
export function categoryLabel(c: string, lang: Lang): string {
  const d = BY_ID.get(c)
  return d ? d[lang === 'de' ? 0 : 1] : c
}

/** Accept an id, a German/English default name (any case) or an own category name. */
export function toCategory(v: string | undefined): string | undefined {
  const s = v?.trim()
  if (!s) return undefined
  if (BY_ID.has(s)) return s
  const low = s.toLowerCase()
  for (const [id, [de, en]] of BY_ID) if (de.toLowerCase() === low || en.toLowerCase() === low) return id
  return s
}

/** Categories offered: the configured list (or the defaults) plus any used by items. */
export function allCategories(configured: string[], used: (string | undefined)[]): string[] {
  const list = configured.length ? [...configured] : [...DEFAULT_CATEGORY_IDS]
  for (const c of used) if (c && !list.includes(c)) list.push(c)
  return list
}
