import { useEffect, useRef, useState, type InputHTMLAttributes } from 'react'
import { useLang } from '../i18n'
import type { Item, Kind } from '../types'

export const KIND_ICON: Record<Kind, string> = { book: '📖', game: '🎲', dvd: '📀', cd: '💿' }

/**
 * Text input that saves on blur / Enter instead of on every keystroke.
 */
export function TextField({ value, onCommit, multiline, ...rest }: { value: string; onCommit(v: string): void; multiline?: boolean } & Omit<InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'>) {
  const [draft, setDraft] = useState(value)
  const focused = useRef(false)
  useEffect(() => {
    if (!focused.current) setDraft(value)
  }, [value])
  const commit = () => {
    focused.current = false
    if (draft !== value) onCommit(draft)
  }
  const common = { value: draft, onFocus: () => (focused.current = true), onBlur: commit }
  if (multiline) return <textarea rows={3} {...common} placeholder={rest.placeholder} aria-label={rest['aria-label']} onChange={(e) => setDraft(e.target.value)} />
  return <input {...rest} {...common} onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()} />
}

export function Stars({ value, onChange, size = 'md' }: { value: number; onChange?(v: number): void; size?: 'sm' | 'md' }) {
  const { t } = useLang()
  if (!onChange)
    return value ? (
      <span className={`stars stars-${size}`} aria-label={t('rating.n', { n: value })}>
        {'★'.repeat(value)}
        <span className="stars-off">{'★'.repeat(5 - value)}</span>
      </span>
    ) : null
  return (
    <span className={`stars stars-${size} stars-edit`} role="radiogroup" aria-label={t('rating')}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button key={n} role="radio" aria-checked={value === n} aria-label={t('rating.n', { n })} className={n <= value ? 'on' : ''} onClick={() => onChange(value === n ? 0 : n)}>
          ★
        </button>
      ))}
    </span>
  )
}

/** Cover image with a coloured placeholder showing the title when there is none (or it fails). */
export function Cover({ item, size = 'sm' }: { item: Pick<Item, 'title' | 'kind' | 'coverUrl' | 'coverData'>; size?: 'sm' | 'lg' }) {
  const src = item.coverData ?? item.coverUrl
  const [failed, setFailed] = useState(false)
  useEffect(() => setFailed(false), [src])
  if (src && !failed) return <img className={`cover cover-${size}`} src={src} alt="" loading="lazy" onError={() => setFailed(true)} />
  let h = 0
  for (const c of item.title) h = (h * 31 + c.charCodeAt(0)) % 360
  return (
    <div className={`cover cover-${size} cover-ph`} style={{ background: `hsl(${h} 45% 55%)` }} aria-hidden>
      <span className="cover-ph-icon">{KIND_ICON[item.kind]}</span>
      {size === 'lg' && <span className="cover-ph-title">{item.title}</span>}
    </div>
  )
}

export function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: { value: T; label: string }[]; onChange(v: T): void; label?: string }) {
  return (
    <div className="seg" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} role="radio" aria-checked={value === o.value} className={value === o.value ? 'on' : ''} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

/** Datalist-backed input for rooms, shelves and people. */
export function Suggest({ id, value, options, onChange, placeholder, label }: { id: string; value: string; options: string[]; onChange(v: string): void; placeholder?: string; label?: string }) {
  return (
    <>
      <input list={id} value={value} placeholder={placeholder} aria-label={label} onChange={(e) => onChange(e.target.value)} />
      <datalist id={id}>
        {options.map((o) => (
          <option key={o} value={o} />
        ))}
      </datalist>
    </>
  )
}
