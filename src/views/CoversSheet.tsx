import { useMemo, useRef, useState } from 'react'
import { Cover, Segmented } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useRooms } from '../components/usePlaces'
import { useLang } from '../i18n'
import { coverFromPhoto } from '../logic/image'
import { sortItems } from '../logic/items'
import { useStore } from '../store'
import type { Item } from '../types'
import { useUI } from '../ui'

/**
 * Add cover photos to existing entries: one at a time (camera / gallery per row), or many photos
 * at once, handed out in list order to the entries that still have no cover.
 * Without `ids` the list holds all entries without a cover, in shelf order.
 */
export function CoversSheet({ ids }: { ids?: string[] }) {
  const { t, lang } = useLang()
  const ui = useUI()
  const { items, byId, updateItem } = useStore()
  const rooms = useRooms()
  const [room, setRoom] = useState('all')
  /** which photo: the front cover or the spine (for the shelf view) */
  const [field, setField] = useState<'coverData' | 'spineData'>('coverData')
  const has = (i: Item) => (field === 'coverData' ? !!i.coverData : !!i.spineData)
  // the list is fixed when the sheet opens (and when room or photo kind change), so entries don't vanish once they got a photo
  const list = useMemo(() => {
    const base = ids ? ids.map((id) => byId.get(id)).filter((i) => !!i) : items.filter((i) => (field === 'coverData' ? !i.coverData && !i.coverUrl : !i.spineData))
    return sortItems(base.filter((i) => room === 'all' || (i.room ?? '') === room), 'place', lang).map((i) => i.id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids, room, field])
  const [busy, setBusy] = useState('')
  const target = useRef<string | null>(null)
  const camRef = useRef<HTMLInputElement>(null)
  const galRef = useRef<HTMLInputElement>(null)
  const manyRef = useRef<HTMLInputElement>(null)

  const live = list.map((id) => byId.get(id)).filter((i) => !!i)
  const missing = live.filter((i) => !has(i))

  const pick = (id: string, camera: boolean) => {
    target.current = id
    ;(camera ? camRef : galRef).current?.click()
  }
  const onOne = async (files: FileList | null) => {
    const id = target.current
    if (!files?.[0] || !id) return
    setBusy(t('covers.saving'))
    try {
      updateItem(id, { [field]: await coverFromPhoto(files[0]) })
    } finally {
      setBusy('')
    }
  }
  const onMany = async (files: FileList | null) => {
    if (!files?.length) return
    const photos = [...files]
    const targets = missing.slice(0, photos.length)
    if (!confirm(t('covers.manyConfirm', { n: Math.min(photos.length, targets.length), first: targets[0]?.title ?? '' }) + (photos.length > targets.length ? ' ' + t('covers.manyExtra', { n: photos.length - targets.length }) : ''))) return
    try {
      for (let i = 0; i < targets.length; i++) {
        setBusy(t('covers.savingN', { i: i + 1, n: targets.length }))
        updateItem(targets[i].id, { [field]: await coverFromPhoto(photos[i]) })
      }
    } finally {
      setBusy('')
    }
  }

  return (
    <Sheet title={`📷 ${t('covers.title')}`} onClose={ui.close}>
      <p className="muted small">{t('covers.intro')}</p>
      <Segmented<'coverData' | 'spineData'>
        value={field}
        onChange={setField}
        options={[
          { value: 'coverData', label: `📕 ${t('covers.modeCover')}` },
          { value: 'spineData', label: `📚 ${t('covers.modeSpine')}` },
        ]}
      />
      {!ids && (
        <label>
          {t('field.room')}
          <select value={room} onChange={(e) => setRoom(e.target.value)}>
            <option value="all">{t('any')}</option>
            {rooms.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
            <option value="">{t('places.none')}</option>
          </select>
        </label>
      )}
      <p>
        <strong>{t(field === 'coverData' ? 'covers.left' : 'covers.leftSpine', { n: missing.length, total: live.length })}</strong>
      </p>
      <button className="btn primary wide" disabled={!missing.length || !!busy} onClick={() => manyRef.current?.click()}>
        🖼 {t('covers.many')}
      </button>
      <p className="muted small">{t('covers.manyHint')}</p>
      {busy && (
        <p className="busy">
          <span className="spinner" aria-hidden /> {busy}
        </p>
      )}
      <div className="list">
        {live.map((i) => (
          <div key={i.id} className="cover-row">
            {field === 'spineData' && i.spineData ? <img className="review-spine" src={i.spineData} alt="" /> : <Cover item={i} />}
            <span className="item-row-main">
              <span className="item-row-title">
                {i.title}
                {i.volume && <span className="muted"> · {i.volume}</span>}
              </span>
              {i.creators.length > 0 && <span className="item-row-sub">{i.creators.join(', ')}</span>}
              {i.room && <span className="item-row-place">{i.room}</span>}
            </span>
            <span className="row gap">
              {has(i) && <span aria-label={t('covers.done')}>✓</span>}
              <button className="icon-btn" disabled={!!busy} onClick={() => pick(i.id, true)} aria-label={t('cover.camera')}>
                📷
              </button>
              <button className="icon-btn" disabled={!!busy} onClick={() => pick(i.id, false)} aria-label={t('cover.gallery')}>
                🖼
              </button>
            </span>
          </div>
        ))}
      </div>
      {live.length === 0 && <p className="empty muted">{t(field === 'coverData' ? 'covers.none' : 'covers.noneSpine')}</p>}
      <input ref={camRef} type="file" accept="image/*" capture="environment" hidden onChange={(e) => (onOne(e.target.files), (e.target.value = ''))} />
      <input ref={galRef} type="file" accept="image/*" hidden onChange={(e) => (onOne(e.target.files), (e.target.value = ''))} />
      <input ref={manyRef} type="file" accept="image/*" multiple hidden onChange={(e) => (onMany(e.target.files), (e.target.value = ''))} />
    </Sheet>
  )
}
