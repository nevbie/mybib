import { useEffect, useRef, useState } from 'react'
import { Cover, Segmented, Suggest } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useRooms } from '../components/usePlaces'
import { useLang } from '../i18n'
import { findDuplicate } from '../logic/items'
import { classifyCode } from '../logic/isbn'
import { lookupEan, lookupIsbn, type Candidate } from '../logic/lookup'
import { useStore } from '../store'
import type { Item } from '../types'
import { useUI } from '../ui'

// Chrome on Android ships the Shape Detection API; TypeScript's DOM lib doesn't know it yet.
interface DetectedBarcode {
  rawValue: string
}
interface BarcodeDetectorLike {
  detect(source: CanvasImageSource): Promise<DetectedBarcode[]>
}
declare const BarcodeDetector: { new (o: { formats: string[] }): BarcodeDetectorLike } | undefined

type Mode = 'own' | 'wish' | 'check'
/** one code of a batch scan */
interface Queued {
  code: string
  state: 'busy' | 'found' | 'none'
  cand?: Candidate
  dup?: Item
  take: boolean
}
type Phase = { p: 'scan' } | { p: 'busy'; code: string } | { p: 'found'; code: string; list: Candidate[]; dup?: Item } | { p: 'none'; code: string; dup?: Item }

export function ScanSheet() {
  const { t } = useLang()
  const ui = useUI()
  const { items, settings, addItems, updateSettings } = useStore()
  const [mode, setMode] = useState<Mode>('own')
  const [phase, setPhase] = useState<Phase>({ p: 'scan' })
  const [manual, setManual] = useState('')
  const [camError, setCamError] = useState('')
  const [added, setAdded] = useState<Item[]>([])
  const [room, setRoom] = useState(settings.lastRoom)
  /** batch: keep scanning, collect every code, add them all at the end */
  const [batch, setBatch] = useState(false)
  const [queue, setQueue] = useState<Queued[]>([])
  const batchRef = useRef(batch)
  batchRef.current = batch
  // the camera loop keeps the first render's functions – read the current mode through a ref
  const modeRef = useRef(mode)
  modeRef.current = mode
  const queueRef = useRef(queue)
  queueRef.current = queue
  const rooms = useRooms()
  const videoRef = useRef<HTMLVideoElement>(null)
  const phaseRef = useRef(phase)
  phaseRef.current = phase
  const itemsRef = useRef(items)
  itemsRef.current = items
  const supported = typeof BarcodeDetector !== 'undefined'

  const lookup = async (code: string, type: string) =>
    type === 'isbn' ? [await lookupIsbn(code, settings.googleBooksKey)].filter((x): x is Candidate => !!x) : await lookupEan(code)

  /** Batch scan: queue the code (once), look it up in the background. */
  const enqueue = async (code: string, type: string) => {
    if (queueRef.current.some((q) => q.code === code)) return
    navigator.vibrate?.(60)
    const first = itemsRef.current.find((i) => i.isbn === code)
    setQueue((q) => [{ code, state: 'busy', dup: first, take: !first }, ...q])
    const list = await lookup(code, type).catch(() => [])
    const cand = list[0]
    const dup = first ?? (cand ? findDuplicate(itemsRef.current, cand) : undefined)
    setQueue((q) => q.map((x) => (x.code === code ? { ...x, state: cand ? 'found' : 'none', cand, dup, take: !!cand && !dup } : x)))
  }

  const handle = async (raw: string) => {
    const c = classifyCode(raw)
    if (c.type === 'invalid') {
      alert(t('scan.invalid'))
      return
    }
    if (batchRef.current && modeRef.current !== 'check') return enqueue(c.code, c.type)
    navigator.vibrate?.(60)
    setPhase({ p: 'busy', code: c.code })
    const dup = itemsRef.current.find((i) => i.isbn === c.code)
    const list = await lookup(c.code, c.type)
    const dup2 = dup ?? (list[0] ? findDuplicate(itemsRef.current, { ...list[0], title: list[0].title }) : undefined)
    setPhase(list.length ? { p: 'found', code: c.code, list, dup: dup2 } : { p: 'none', code: c.code, dup: dup2 })
  }

  // camera + detection loop
  useEffect(() => {
    if (!supported) return
    let stream: MediaStream | null = null
    let timer = 0
    let stopped = false
    let last = ''
    const detector = new BarcodeDetector!({ formats: ['ean_13', 'ean_8', 'upc_a', 'upc_e'] })
    const tick = async () => {
      if (stopped) return
      const v = videoRef.current
      if (v && v.readyState >= 2 && phaseRef.current.p === 'scan') {
        try {
          const codes = await detector.detect(v)
          const value = codes[0]?.rawValue
          // require the same reading twice in a row to avoid misreads
          if (value && value === last && classifyCode(value).type !== 'invalid') {
            last = ''
            handle(value)
          } else last = value ?? ''
        } catch {
          /* frame not ready */
        }
      }
      timer = window.setTimeout(tick, 200)
    }
    navigator.mediaDevices
      ?.getUserMedia({ video: { facingMode: 'environment', width: { ideal: 1280 } }, audio: false })
      .then((s) => {
        if (stopped) return s.getTracks().forEach((tr) => tr.stop())
        stream = s
        if (videoRef.current) {
          videoRef.current.srcObject = s
          videoRef.current.play().catch(() => {})
        }
        tick()
      })
      .catch((e) => setCamError(String(e?.message ?? e)))
    return () => {
      stopped = true
      clearTimeout(timer)
      stream?.getTracks().forEach((tr) => tr.stop())
    }
  }, [])

  const add = async (c: Candidate) => {
    const { via: _via, ...draft } = c
    const [item] = await addItems([{ ...draft, owned: mode !== 'wish', room: mode === 'wish' ? undefined : room || undefined, source: 'isbn' }])
    updateSettings({ lastRoom: room })
    setAdded((a) => [item, ...a])
    setPhase({ p: 'scan' })
  }

  const addQueued = async () => {
    const take = queue.filter((q) => q.take && q.cand)
    if (!take.length) return
    const drafts = take.map((q) => {
      const { via: _via, ...draft } = q.cand!
      return { ...draft, owned: mode !== 'wish', room: mode === 'wish' ? undefined : room || undefined, source: 'isbn' as const }
    })
    const created = await addItems(drafts)
    updateSettings({ lastRoom: room })
    setAdded((a) => [...created, ...a])
    setQueue((q) => q.filter((x) => !take.includes(x)))
    alert(t('scan.addedN', { n: created.length }))
  }

  const editAndAdd = (c: Partial<Candidate> & { title: string }) => {
    const { via: _via, ...draft } = c as Candidate
    ui.openForm(undefined, { ...draft, owned: mode !== 'wish', room: room || undefined, source: 'isbn' })
    setPhase({ p: 'scan' })
  }

  return (
    <Sheet title={t('scan.title')} onClose={ui.close}>
      <Segmented<Mode>
        value={mode}
        label={t('scan.mode')}
        onChange={setMode}
        options={[
          { value: 'own', label: t('scan.mode.own') },
          { value: 'wish', label: t('scan.mode.wish') },
          { value: 'check', label: t('scan.mode.check') },
        ]}
      />
      {mode !== 'check' && (
        <label className="toggle">
          <input type="checkbox" checked={batch} onChange={(e) => (setBatch(e.target.checked), setPhase({ p: 'scan' }))} />
          {t('scan.batch')}
        </label>
      )}
      {batch && mode !== 'check' && <p className="muted small">{t('scan.batchHint')}</p>}
      {mode === 'own' && (
        <div className="row gap">
          <Suggest id="s-rooms" value={room} options={rooms} placeholder={t('field.room')} label={t('field.room')} onChange={setRoom} />
        </div>
      )}

      {supported && !camError ? (
        <div className="scanner">
          <video ref={videoRef} playsInline muted />
          <div className="scanner-line" />
        </div>
      ) : (
        <p className="notice small">{camError ? t('scan.camError', { e: camError }) : t('scan.unsupported')}</p>
      )}

      <form
        className="row gap"
        onSubmit={(e) => {
          e.preventDefault()
          if (manual.trim()) handle(manual)
          setManual('')
        }}
      >
        <input inputMode="numeric" value={manual} onChange={(e) => setManual(e.target.value)} placeholder={t('scan.manual')} aria-label={t('scan.manual')} />
        <button className="btn">{t('ok')}</button>
      </form>

      {phase.p === 'busy' && <p className="muted">{t('scan.looking', { code: phase.code })}</p>}

      {(phase.p === 'found' || phase.p === 'none') && phase.dup && (
        <div className="notice">
          <p>
            <strong>{mode === 'check' ? '✅ ' : '⚠︎ '}</strong>
            {t('scan.have', { title: phase.dup.title, place: phase.dup.room || '–' })}
          </p>
          <button className="btn small" onClick={() => ui.openItem(phase.dup!.id)}>
            {t('scan.open')}
          </button>
        </div>
      )}
      {mode === 'check' && (phase.p === 'found' || phase.p === 'none') && !phase.dup && <p className="notice">❌ {t('scan.notHave')}</p>}

      {phase.p === 'found' &&
        phase.list.map((c, i) => (
          <div key={i} className="card result">
            <Cover item={{ title: c.title, kind: c.kind ?? 'book', coverUrl: c.coverUrl }} size="lg" />
            <div className="col gap">
              <strong>{c.title}</strong>
              {c.subtitle && <span className="muted">{c.subtitle}</span>}
              <span>{c.creators?.join(', ')}</span>
              <span className="muted small">{[c.publisher, c.year, c.via].filter(Boolean).join(' · ')}</span>
              {mode !== 'check' && (
                <div className="row gap wrap">
                  <button className="btn primary" onClick={() => add(c)}>
                    ＋ {mode === 'wish' ? t('scan.addWish') : t('scan.add')}
                  </button>
                  <button className="btn" onClick={() => editAndAdd(c)}>
                    ✎ {t('scan.edit')}
                  </button>
                </div>
              )}
            </div>
          </div>
        ))}
      {phase.p === 'none' && (
        <div className="card">
          <p>{t('scan.notFound', { code: phase.code })}</p>
          {mode !== 'check' && (
            <button className="btn" onClick={() => editAndAdd({ title: '', isbn: phase.code, kind: phase.code.startsWith('97') ? 'book' : 'dvd' })}>
              ✍️ {t('scan.manualAdd')}
            </button>
          )}
        </div>
      )}
      {phase.p !== 'scan' && phase.p !== 'busy' && (
        <button className="btn ghost wide" onClick={() => setPhase({ p: 'scan' })}>
          {t('scan.next')}
        </button>
      )}

      {batch && mode !== 'check' && queue.length > 0 && (
        <>
          <div className="row between center">
            <h3>{t('scan.queue', { n: queue.length })}</h3>
            <button className="btn primary small" disabled={!queue.some((q) => q.take && q.cand)} onClick={addQueued}>
              ＋ {t('scan.addAll', { n: queue.filter((q) => q.take && q.cand).length })}
            </button>
          </div>
          <div className="review">
            {queue.map((q) => (
              <div key={q.code} className={`review-row ${q.take ? '' : 'off'}`}>
                <input type="checkbox" checked={q.take} disabled={!q.cand} onChange={(e) => setQueue((qs) => qs.map((x) => (x === q ? { ...x, take: e.target.checked } : x)))} aria-label={q.code} />
                <Cover item={{ title: q.cand?.title ?? q.code, kind: q.cand?.kind ?? 'book', coverUrl: q.cand?.coverUrl }} />
                <div className="col">
                  <strong>{q.state === 'busy' ? t('scan.looking', { code: q.code }) : (q.cand?.title ?? q.code)}</strong>
                  {q.cand?.creators?.length ? <span className="muted small">{q.cand.creators.join(', ')}</span> : null}
                  <div className="row gap center small">
                    {q.dup && (
                      <button className="badge badge-wish" onClick={() => ui.openItem(q.dup!.id)}>
                        {t('scan.dupShort')}: {q.dup.title}
                      </button>
                    )}
                    {q.state === 'none' && (
                      <button className="link small" onClick={() => editAndAdd({ title: '', isbn: q.code, kind: q.code.startsWith('97') ? 'book' : 'dvd' })}>
                        {t('scan.notFoundShort')} – {t('scan.manualAdd')}
                      </button>
                    )}
                  </div>
                </div>
                <button className="icon-btn" onClick={() => setQueue((qs) => qs.filter((x) => x !== q))} aria-label={t('close')}>
                  ✕
                </button>
              </div>
            ))}
          </div>
        </>
      )}

      {added.length > 0 && (
        <>
          <h3>{t('scan.added', { n: added.length })}</h3>
          <ul className="small">
            {added.map((i) => (
              <li key={i.id}>{i.title}</li>
            ))}
          </ul>
        </>
      )}
    </Sheet>
  )
}
