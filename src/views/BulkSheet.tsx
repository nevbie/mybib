import { useEffect, useMemo, useRef, useState } from 'react'
import { Sheet } from '../components/Sheet'
import { useLang } from '../i18n'
import { bulkTargets, missingInfo } from '../logic/bulk'
import { today } from '../logic/items'
import { enrichPatch, findBestMatch, takeGoogleProblem } from '../logic/lookup'
import { useStore } from '../store'
import type { Item } from '../types'
import { useUI } from '../ui'

type Phase = 'idle' | 'running' | 'done' | 'stopped' | 'quota' | 'key'

/** Complete covers, publisher, year, ISBN and blurb of all books via Google Books (+ Open Library). */
export function BulkSheet() {
  const { t } = useLang()
  const ui = useUI()
  const { items, settings, updateItem } = useStore()
  const [retry, setRetry] = useState(false)
  const [phase, setPhase] = useState<Phase>('idle')
  const [done, setDone] = useState(0)
  const [total, setTotal] = useState(0)
  const [current, setCurrent] = useState('')
  const [found, setFound] = useState<Item[]>([])
  const [missed, setMissed] = useState<Item[]>([])
  const stopRef = useRef(false)
  const targets = useMemo(() => bulkTargets(items, retry), [items, retry, phase === 'idle'])
  const triedBefore = useMemo(() => bulkTargets(items, true).length - bulkTargets(items, false).length, [items])

  // don't let the phone sleep while it works through hundreds of books
  useEffect(() => {
    if (phase !== 'running') return
    let lock: { release(): Promise<void> } | undefined
    ;(navigator as Navigator & { wakeLock?: { request(t: 'screen'): Promise<{ release(): Promise<void> }> } }).wakeLock
      ?.request('screen')
      .then((l) => (lock = l))
      .catch(() => {})
    return () => void lock?.release().catch(() => {})
  }, [phase])

  const run = async () => {
    const list = [...targets]
    stopRef.current = false
    takeGoogleProblem()
    setPhase('running')
    setTotal(list.length)
    setDone(0)
    setFound([])
    setMissed([])
    for (let n = 0; n < list.length; n++) {
      if (stopRef.current) return setPhase('stopped')
      const item = list[n]
      setCurrent(item.title)
      const best = await findBestMatch(item, settings.googleBooksKey).catch(() => null)
      const problem = takeGoogleProblem()
      if (problem && !best) {
        // leave this item untried so the next run picks it up again
        return setPhase(problem)
      }
      if (best) {
        const patch = enrichPatch(item, best)
        // without a known author a title-only match may be a different book – ask to check
        updateItem(item.id, { ...patch, lookedUp: today(), ...(item.creators.length ? {} : { needsCheck: true }) })
        if (Object.keys(patch).length) setFound((f) => [item, ...f])
        else setMissed((m) => [...m, item])
      } else {
        updateItem(item.id, { lookedUp: today() })
        setMissed((m) => [...m, item])
      }
      setDone(n + 1)
      if (problem) return setPhase(problem)
      // stay well below Google's per-minute limit
      await new Promise((r) => setTimeout(r, 400))
    }
    setCurrent('')
    setPhase('done')
  }

  const running = phase === 'running'
  const pct = total ? Math.round((done / total) * 100) : 0

  return (
    <Sheet
      title={t('bulk.title')}
      onClose={() => {
        stopRef.current = true
        ui.close()
      }}
      footer={
        running ? (
          <button className="btn wide" onClick={() => (stopRef.current = true)}>
            ■ {t('bulk.stop')}
          </button>
        ) : (
          <button className="btn primary wide" onClick={run} disabled={!targets.length}>
            {t('bulk.start', { n: targets.length })}
          </button>
        )
      }
    >
      <p className="muted small">{t('bulk.intro')}</p>
      {!settings.googleBooksKey && (
        <div className="notice small">
          <p>{t('bulk.noKey')}</p>
          <button className="btn small" onClick={() => ui.go('settings')}>
            ⚙︎ {t('nav.settings')}
          </button>
        </div>
      )}

      {phase === 'idle' && (
        <>
          <p>{targets.length ? t('bulk.count', { n: targets.length }) : t('bulk.nothing')}</p>
          {triedBefore > 0 && (
            <label className="toggle">
              <input type="checkbox" checked={retry} onChange={(e) => setRetry(e.target.checked)} />
              {t('bulk.retry', { n: triedBefore })}
            </label>
          )}
        </>
      )}

      {phase !== 'idle' && (
        <>
          <div className="progress" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
            <div style={{ width: `${pct}%` }} />
          </div>
          <p className="small">
            {done} / {total} · ✓ {found.length} · – {missed.length}
          </p>
          {running && current && (
            <p className="busy small">
              <span className="spinner" aria-hidden /> {current}
            </p>
          )}
          {phase === 'done' && <p>{t('bulk.done', { found: found.length, missed: missed.length })}</p>}
          {phase === 'stopped' && <p>{t('bulk.stopped')}</p>}
          {phase === 'quota' && <p className="notice">{t('bulk.quota')}</p>}
          {phase === 'key' && <p className="notice">{t('bulk.badKey')}</p>}
        </>
      )}

      {found.length > 0 && (
        <>
          <h3>{t('bulk.found', { n: found.length })}</h3>
          <ul className="bulk-list small">
            {found.slice(0, 30).map((i) => (
              <li key={i.id}>
                <button className="link" onClick={() => ui.openItem(i.id)}>
                  {i.title}
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
      {missed.length > 0 && !running && (
        <>
          <h3>{t('bulk.missed', { n: missed.length })}</h3>
          <p className="muted small">{t('bulk.missedHint')}</p>
          <ul className="bulk-list small">
            {missed.map((i) => (
              <li key={i.id}>
                <button className="link" onClick={() => ui.openItem(i.id)}>
                  {i.title}
                </button>{' '}
                <span className="muted">({missingInfo(i).map((f) => t(`bulk.field.${f}`)).join(', ')})</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </Sheet>
  )
}
