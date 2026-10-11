import { useMemo, useRef, useState } from 'react'
import { Cover } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useLang } from '../i18n'
import { rotateDataUrl } from '../logic/image'
import { RecognizeError } from '../logic/recognized'
import { sortItems } from '../logic/items'
import { useStore } from '../store'
import { useUI } from '../ui'

/** Covers per request – small thumbnails, so a batch stays cheap and fast. */
const BATCH = 12

/**
 * Turn own cover photos upright: automatically (Claude looks at each cover and says how far to turn it)
 * or by hand, 90° per tap. Without `ids`: all entries with an own cover photo.
 */
export function RotateSheet({ ids }: { ids?: string[] }) {
  const { t, lang } = useLang()
  const ui = useUI()
  const { items, byId, settings, updateItem } = useStore()
  const list = useMemo(() => {
    const base = ids ? ids.map((id) => byId.get(id)).filter((i) => !!i) : items
    return sortItems(base.filter((i) => i.coverData), 'place', lang).map((i) => i.id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids])
  const live = list.map((id) => byId.get(id)).filter((i) => !!i && !!i.coverData)
  const [busy, setBusy] = useState('')
  const [turned, setTurned] = useState<Set<string>>(new Set())
  const abortRef = useRef<AbortController | null>(null)
  const hasKey = !!settings.claudeKey

  const turn = async (id: string, deg: number) => {
    const i = byId.get(id)
    if (!i?.coverData) return
    updateItem(id, { coverData: await rotateDataUrl(i.coverData, deg) })
  }

  const auto = async () => {
    abortRef.current = new AbortController()
    const { detectRotations } = await import('../logic/ai')
    const done = new Set<string>()
    try {
      for (let start = 0; start < live.length; start += BATCH) {
        const batch = live.slice(start, start + BATCH)
        setBusy(t('rotate.checking', { i: Math.min(start + BATCH, live.length), n: live.length }))
        const degs = await detectRotations({ apiKey: settings.claudeKey, model: settings.claudeModel, images: batch.map((i) => i!.coverData!), signal: abortRef.current.signal })
        for (let k = 0; k < batch.length; k++) {
          if (degs[k]) {
            await turn(batch[k]!.id, degs[k])
            done.add(batch[k]!.id)
          }
        }
      }
      alert(t('rotate.done', { n: done.size, total: live.length }))
    } catch (e) {
      if (!abortRef.current.signal.aborted) alert(e instanceof RecognizeError ? t(`ai.err.${e.code}`) : String(e))
    } finally {
      setTurned(done)
      setBusy('')
    }
  }

  return (
    <Sheet
      title={`⟳ ${t('rotate.title')}`}
      onClose={() => {
        abortRef.current?.abort()
        ui.close()
      }}
    >
      <p className="muted small">{hasKey ? t('rotate.intro') : t('rotate.introNoKey')}</p>
      <button className="btn primary wide" disabled={!hasKey || !live.length || !!busy} onClick={auto}>
        ✨ {t('rotate.auto', { n: live.length })}
      </button>
      {busy && (
        <p className="busy">
          <span className="spinner" aria-hidden /> {busy}
        </p>
      )}
      <div className="list">
        {live.map((i) => (
          <div key={i!.id} className="cover-row">
            <Cover item={i!} />
            <span className="item-row-main">
              <span className="item-row-title">{i!.title}</span>
              {turned.has(i!.id) && <span className="badge badge-rec">⟳ {t('rotate.turned')}</span>}
            </span>
            <span className="row gap">
              <button className="icon-btn" disabled={!!busy} onClick={() => turn(i!.id, 270)} aria-label={t('rotate.left')}>
                ⟲
              </button>
              <button className="icon-btn" disabled={!!busy} onClick={() => turn(i!.id, 90)} aria-label={t('rotate.right')}>
                ⟳
              </button>
            </span>
          </div>
        ))}
      </div>
      {live.length === 0 && <p className="empty muted">{t('rotate.none')}</p>}
    </Sheet>
  )
}
