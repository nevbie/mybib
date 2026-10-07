import { useEffect, useState } from 'react'
import { Cover, Segmented } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useLang } from '../i18n'
import { searchOnline, type Candidate } from '../logic/lookup'
import { useStore } from '../store'
import type { Kind } from '../types'
import { useUI } from '../ui'

const SEARCHABLE: Kind[] = ['book', 'cd', 'dvd']

/** Search Google Books / Open Library / MusicBrainz by title and creator and pick one result. */
export function SearchSheet({ kind: initialKind, title: t0, creator: c0 }: { kind: Kind; title: string; creator: string }) {
  const { t } = useLang()
  const ui = useUI()
  const { settings } = useStore()
  const [kind, setKind] = useState<Kind>(SEARCHABLE.includes(initialKind) ? initialKind : 'book')
  const [title, setTitle] = useState(t0)
  const [creator, setCreator] = useState(c0)
  const [busy, setBusy] = useState(false)
  const [results, setResults] = useState<Candidate[] | null>(null)

  const run = async () => {
    if (!title.trim() && !creator.trim()) return
    setBusy(true)
    setResults(null)
    try {
      setResults(await searchOnline(kind, title, creator, settings.googleBooksKey))
    } finally {
      setBusy(false)
    }
  }
  // search right away when opened with a title
  useEffect(() => {
    if (t0.trim()) run()
  }, [])

  return (
    <Sheet title={t('search.title')} onClose={() => ui.finishSearch(null)}>
      <Segmented<Kind> value={kind} label={t('field.kind')} onChange={setKind} options={SEARCHABLE.map((k) => ({ value: k, label: t(`kind.${k}`) }))} />
      <form
        className="col gap"
        onSubmit={(e) => {
          e.preventDefault()
          run()
        }}
      >
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t('field.title')} aria-label={t('field.title')} />
        <input value={creator} onChange={(e) => setCreator(e.target.value)} placeholder={t(`creator.${kind}`)} aria-label={t(`creator.${kind}`)} />
        <button className="btn primary" disabled={busy}>
          {busy ? t('search.busy') : `🔎 ${t('search.go')}`}
        </button>
      </form>
      {results && results.length === 0 && <p className="muted">{t('search.none')}</p>}
      <div className="list">
        {results?.map((c, i) => (
          <button key={i} className="item-row" onClick={() => ui.finishSearch(c)}>
            <Cover item={{ title: c.title, kind: c.kind ?? kind, coverUrl: c.coverUrl }} />
            <span className="item-row-main">
              <span className="item-row-title">{c.title}</span>
              {c.subtitle && <span className="item-row-sub">{c.subtitle}</span>}
              <span className="item-row-sub">{c.creators?.join(', ')}</span>
              <span className="item-row-meta muted small">
                {[c.publisher, c.year, c.language, c.via].filter(Boolean).join(' · ')}
              </span>
            </span>
          </button>
        ))}
      </div>
    </Sheet>
  )
}
