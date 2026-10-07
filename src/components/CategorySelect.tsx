import type { ReactNode } from 'react'
import { useLang } from '../i18n'
import { categoryLabel, DEFAULT_CATEGORIES } from '../logic/categories'
import { useCategories } from './usePlaces'

/**
 * Category picker grouped like the default list (Kinder & Jugend, Belletristik, Sachbuch);
 * own categories come last. `head` adds options before the list (e.g. "unchanged", "all").
 */
export function CategorySelect({ value, onChange, head, noneValue = '', label }: { value: string; onChange(v: string): void; head?: ReactNode; noneValue?: string; label?: string }) {
  const { t, lang } = useLang()
  const cats = useCategories()
  const grouped = new Set(DEFAULT_CATEGORIES.flatMap((g) => g.items.map(([id]) => id)))
  const own = cats.filter((c) => !grouped.has(c))
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} aria-label={label ?? t('field.category')}>
      {head}
      <option value={noneValue}>{t('cat.none')}</option>
      {DEFAULT_CATEGORIES.map((g) => {
        const items = g.items.filter(([id]) => cats.includes(id))
        return items.length ? (
          <optgroup key={g.group[0]} label={lang === 'de' ? g.group[0] : g.group[1]}>
            {items.map(([id]) => (
              <option key={id} value={id}>
                {categoryLabel(id, lang)}
              </option>
            ))}
          </optgroup>
        ) : null
      })}
      {own.length > 0 && (
        <optgroup label={t('cat.own')}>
          {own.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </optgroup>
      )}
    </select>
  )
}
