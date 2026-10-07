import { useRef, useState } from 'react'
import { KIND_ICON, Suggest } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useRooms, useShelves } from '../components/usePlaces'
import { useLang } from '../i18n'
import { RecognizeError, toDraft } from '../logic/recognized'
import { coverFromPhoto, dataUrlBase64, photoForAI } from '../logic/image'
import { findDuplicate, newId } from '../logic/items'
import { enrichPatch, matchScore, searchOnline } from '../logic/lookup'
import { useStore } from '../store'
import { KINDS, type ItemDraft, type Kind } from '../types'
import { useUI } from '../ui'

interface Row {
  key: string
  draft: ItemDraft & { kind: Kind; creators: string[] }
  confidence: 'high' | 'medium' | 'low'
  remark: string
  selected: boolean
  dupTitle?: string
}

/**
 * Add by photo.
 * - shelf: one or more shelf photos → Claude reads all spines → review list → add.
 * - cover: one front cover → (with key) recognise title → online details → form; own photo becomes the cover.
 */
export function PhotoSheet({ mode }: { mode: 'shelf' | 'cover' }) {
  const { t } = useLang()
  const ui = useUI()
  const { items, settings, addItems, updateSettings } = useStore()
  const [hint, setHint] = useState('')
  const [rows, setRows] = useState<Row[]>([])
  const [status, setStatus] = useState('')
  const [busy, setBusy] = useState(false)
  const [enrich, setEnrich] = useState(true)
  const [room, setRoom] = useState(settings.lastRoom)
  const [shelf, setShelf] = useState(settings.lastShelf)
  const rooms = useRooms()
  const shelves = useShelves(room)
  const camRef = useRef<HTMLInputElement>(null)
  const galRef = useRef<HTMLInputElement>(null)
  const abortRef = useRef<AbortController | null>(null)
  const hasKey = !!settings.claudeKey

  const errorText = (e: unknown) => {
    if (e instanceof RecognizeError) return t(`ai.err.${e.code}`) + (e.code === 'other' || e.code === 'parse' ? ` (${e.message})` : '')
    return String(e)
  }

  const recognize = async (file: File) => {
    const dataUrl = await photoForAI(file)
    // the Anthropic SDK is only downloaded when photo recognition is actually used
    const { recognizePhoto } = await import('../logic/ai')
    return recognizePhoto({ apiKey: settings.claudeKey, model: settings.claudeModel, imageBase64: dataUrlBase64(dataUrl), mediaType: 'image/jpeg', hint, signal: abortRef.current?.signal })
  }

  const onFiles = async (files: FileList | null) => {
    if (!files?.length) return
    const list = [...files]
    if (mode === 'cover') return onCover(list[0])
    setBusy(true)
    abortRef.current = new AbortController()
    try {
      for (let i = 0; i < list.length; i++) {
        setStatus(t('ai.reading', { i: i + 1, n: list.length }))
        try {
          const found = await recognize(list[i])
          setRows((r) => [
            ...r,
            ...found.map((f): Row => {
              const draft = toDraft(f) as Row['draft']
              const dup = findDuplicate(items, draft) ?? r.map((x) => x.draft).find((x) => x.title === draft.title && x.volume === draft.volume)
              return { key: newId(), draft, confidence: f.confidence, remark: f.remark, selected: !dup, dupTitle: dup?.title }
            }),
          ])
        } catch (e) {
          if ((e as Error).name === 'AbortError' || abortRef.current.signal.aborted) break
          alert(errorText(e))
          if (e instanceof RecognizeError && e.code === 'auth') break
        }
      }
    } finally {
      setStatus('')
      setBusy(false)
    }
  }

  const onCover = async (file: File) => {
    setBusy(true)
    try {
      const coverData = await coverFromPhoto(file)
      let draft: ItemDraft = { title: '', coverData, room: room || undefined, shelf: shelf || undefined }
      if (hasKey) {
        setStatus(t('ai.readingCover'))
        abortRef.current = new AbortController()
        try {
          const [first] = await recognize(file)
          if (first) {
            draft = { ...draft, ...toDraft(first), coverData, source: 'search' }
            setStatus(t('ai.enriching'))
            const found = await searchOnline(first.kind, first.title, first.creators[0] ?? '', settings.googleBooksKey)
            const best = found.find((c) => matchScore(first, c) >= 0.75)
            if (best) draft = { ...draft, ...enrichPatch(draft, best), coverUrl: undefined, needsCheck: undefined }
          }
        } catch (e) {
          alert(errorText(e))
        }
      }
      ui.close()
      setTimeout(() => ui.openForm(undefined, draft), 50)
    } finally {
      setBusy(false)
      setStatus('')
    }
  }

  const upd = (key: string, patch: Partial<Row> | ((r: Row) => Partial<Row>)) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...(typeof patch === 'function' ? patch(r) : patch) } : r)))
  const selected = rows.filter((r) => r.selected)

  const addAll = async () => {
    setBusy(true)
    const drafts: ItemDraft[] = []
    try {
      for (let i = 0; i < selected.length; i++) {
        let d: ItemDraft = { ...selected[i].draft, room: room || undefined, shelf: shelf || undefined }
        if (enrich && (d.kind === 'book' || d.kind === 'cd')) {
          setStatus(t('ai.enrichingN', { i: i + 1, n: selected.length }))
          const found = await searchOnline(d.kind!, d.title, d.creators?.[0] ?? '', settings.googleBooksKey).catch(() => [])
          const best = found.find((c) => matchScore(d as { title: string; creators?: string[] }, c) >= 0.75)
          // keep the title as printed on the spine, only fill gaps
          if (best) d = { ...d, ...enrichPatch(d, best) }
          // MusicBrainz asks for max. 1 request per second
          if (d.kind === 'cd') await new Promise((r) => setTimeout(r, 1000))
        }
        drafts.push(d)
      }
      await addItems(drafts)
      updateSettings({ lastRoom: room, lastShelf: shelf })
      alert(t('ai.added', { n: drafts.length }))
      ui.close()
    } finally {
      setBusy(false)
      setStatus('')
    }
  }

  return (
    <Sheet
      title={mode === 'shelf' ? t('add.shelf') : t('add.cover')}
      onClose={() => {
        abortRef.current?.abort()
        ui.close()
      }}
      footer={
        rows.length > 0 && (
          <button className="btn primary wide" onClick={addAll} disabled={busy || !selected.length}>
            {t('ai.addN', { n: selected.length })}
          </button>
        )
      }
    >
      {mode === 'shelf' && !hasKey && (
        <div className="notice">
          <p>{t('ai.noKey')}</p>
          <button className="btn small" onClick={() => ui.go('settings')}>
            ⚙︎ {t('nav.settings')}
          </button>
        </div>
      )}
      {mode === 'cover' && <p className="muted small">{hasKey ? t('ai.coverHint') : t('ai.coverNoKey')}</p>}
      {mode === 'shelf' && hasKey && <p className="muted small">{t('ai.shelfHint')}</p>}

      <div className="row gap">
        <Suggest id="p-rooms" value={room} options={rooms} placeholder={t('field.room')} label={t('field.room')} onChange={setRoom} />
        <Suggest id="p-shelves" value={shelf} options={shelves} placeholder={t('field.shelf')} label={t('field.shelf')} onChange={setShelf} />
      </div>
      {hasKey && <input value={hint} onChange={(e) => setHint(e.target.value)} placeholder={t('ai.hintPh')} aria-label={t('ai.hintPh')} />}

      <div className="row gap">
        <button className="btn primary" disabled={busy || (mode === 'shelf' && !hasKey)} onClick={() => camRef.current?.click()}>
          📷 {t('ai.camera')}
        </button>
        <button className="btn" disabled={busy || (mode === 'shelf' && !hasKey)} onClick={() => galRef.current?.click()}>
          🖼 {t('ai.gallery')}
        </button>
      </div>
      <input ref={camRef} type="file" accept="image/*" capture="environment" hidden onChange={(e) => (onFiles(e.target.files), (e.target.value = ''))} />
      <input ref={galRef} type="file" accept="image/*" multiple={mode === 'shelf'} hidden onChange={(e) => (onFiles(e.target.files), (e.target.value = ''))} />

      {status && (
        <p className="busy">
          <span className="spinner" aria-hidden /> {status}
        </p>
      )}

      {rows.length > 0 && (
        <>
          <div className="row between center">
            <h3>{t('ai.found', { n: rows.length })}</h3>
            <button className="link" onClick={() => setRows((rs) => rs.map((r) => ({ ...r, selected: !selected.length })))}>
              {selected.length ? t('ai.none') : t('ai.all')}
            </button>
          </div>
          <label className="toggle">
            <input type="checkbox" checked={enrich} onChange={(e) => setEnrich(e.target.checked)} />
            {t('ai.enrich')}
          </label>
          <div className="review">
            {rows.map((r) => (
              <div key={r.key} className={`review-row ${r.selected ? '' : 'off'}`}>
                <input type="checkbox" checked={r.selected} onChange={(e) => upd(r.key, { selected: e.target.checked })} aria-label={t('ai.take')} />
                <div className="col">
                  <input className="review-title" value={r.draft.title} onChange={(e) => upd(r.key, (x) => ({ draft: { ...x.draft, title: e.target.value } }))} aria-label={t('field.title')} />
                  <input className="review-sub" value={r.draft.creators.join(', ')} placeholder={t(`creator.${r.draft.kind}`)} onChange={(e) => upd(r.key, (x) => ({ draft: { ...x.draft, creators: e.target.value.split(',').map((s) => s.trim()).filter(Boolean) } }))} aria-label={t(`creator.${r.draft.kind}`)} />
                  <div className="row gap center small">
                    <select value={r.draft.kind} onChange={(e) => upd(r.key, (x) => ({ draft: { ...x.draft, kind: e.target.value as Kind } }))} aria-label={t('field.kind')}>
                      {KINDS.map((k) => (
                        <option key={k} value={k}>
                          {KIND_ICON[k]} {t(`kind.${k}`)}
                        </option>
                      ))}
                    </select>
                    {[r.draft.series, r.draft.volume].filter(Boolean).join(' ')}
                    {r.confidence !== 'high' && <span className="badge badge-check">{t(`ai.conf.${r.confidence}`)}</span>}
                    {r.dupTitle && <span className="badge badge-wish">{t('ai.dup')}</span>}
                  </div>
                  {r.remark && <span className="muted small">{r.remark}</span>}
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </Sheet>
  )
}
