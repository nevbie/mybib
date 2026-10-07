import { useState } from 'react'
import { CategorySelect } from '../components/CategorySelect'
import { Sheet } from '../components/Sheet'
import { useRooms } from '../components/usePlaces'
import { useLang } from '../i18n'
import { useStore } from '../store'
import { FORMATS, KINDS, STATUSES, type Item } from '../types'
import { useUI } from '../ui'

/** '' = leave unchanged */
type Choice = string

const NONE_ROOM = '\u0000none'
const NEW_ROOM = '\u0000new'

/** Change room, kind, status, format, wishlist, recommendation, rating or tags of many items at once. */
export function BulkEditSheet({ ids }: { ids: string[] }) {
  const { t } = useLang()
  const ui = useUI()
  const { byId, updateItems, removeItems } = useStore()
  const rooms = useRooms()
  const [room, setRoom] = useState<Choice>('')
  const [newRoom, setNewRoom] = useState('')
  const [kind, setKind] = useState<Choice>('')
  const [category, setCategory] = useState<Choice>('')
  const [status, setStatus] = useState<Choice>('')
  const [format, setFormat] = useState<Choice>('')
  const [owned, setOwned] = useState<Choice>('')
  const [recommend, setRecommend] = useState<Choice>('')
  const [rating, setRating] = useState<Choice>('')
  const [addTag, setAddTag] = useState('')
  const [removeTag, setRemoveTag] = useState('')
  const [checked, setChecked] = useState(false)

  const live = ids.filter((id) => byId.has(id))
  const n = live.length
  const allTags = [...new Set(live.flatMap((id) => byId.get(id)!.tags))].sort()
  const kindForLabels = (() => {
    const kinds = new Set(live.map((id) => byId.get(id)!.kind))
    return kinds.size === 1 ? [...kinds][0] : 'book'
  })()

  const targetRoom = room === NEW_ROOM ? newRoom.trim() : room === NONE_ROOM ? '' : room
  const changes = [room && (room !== NEW_ROOM || newRoom.trim()), category, kind, status, format, owned, recommend, rating, addTag.trim(), removeTag, checked].filter(Boolean).length

  const apply = () => {
    const patch: Partial<Item> = {}
    if (room && (room !== NEW_ROOM || targetRoom)) patch.room = targetRoom || undefined
    if (kind) patch.kind = kind as Item['kind']
    if (category) patch.category = category === NONE_ROOM ? undefined : category
    if (status) patch.status = status as Item['status']
    if (format) patch.format = format as Item['format']
    if (owned) patch.owned = owned === 'yes'
    if (recommend) patch.recommend = recommend === 'yes'
    if (rating) patch.rating = Number(rating)
    if (checked) patch.needsCheck = undefined
    const tag = addTag.trim()
    updateItems(live, (i) => ({
      ...patch,
      ...(tag || removeTag ? { tags: [...new Set([...i.tags.filter((x) => x !== removeTag), ...(tag ? [tag] : [])])] } : {}),
    }))
    ui.close()
  }

  const del = () => {
    if (!confirm(t('bulkEdit.deleteConfirm', { n }))) return
    removeItems(live)
    ui.close()
  }

  const unchanged = <option value="">{t('bulkEdit.unchanged')}</option>
  const yesNo = (
    <>
      {unchanged}
      <option value="yes">{t('bulkEdit.yes')}</option>
      <option value="no">{t('bulkEdit.no')}</option>
    </>
  )

  return (
    <Sheet
      title={t('bulkEdit.title', { n })}
      onClose={ui.close}
      footer={
        <div className="row gap">
          <button className="btn primary" onClick={apply} disabled={!changes || !n}>
            {t('bulkEdit.apply', { n })}
          </button>
          <button className="btn danger ghost" onClick={del} disabled={!n} aria-label={t('detail.delete')}>
            🗑
          </button>
        </div>
      }
    >
      <p className="muted small">{t('bulkEdit.intro')}</p>
      <label>
        {t('field.room')}
        <select value={room} onChange={(e) => setRoom(e.target.value)}>
          {unchanged}
          {rooms.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
          <option value={NONE_ROOM}>{t('places.none')}</option>
          <option value={NEW_ROOM}>{t('bulkEdit.newRoom')}</option>
        </select>
      </label>
      {room === NEW_ROOM && <input value={newRoom} onChange={(e) => setNewRoom(e.target.value)} placeholder={t('places.newRoom')} aria-label={t('places.newRoom')} autoFocus />}
      <label>
        {t('field.category')}
        <CategorySelect value={category} onChange={setCategory} noneValue={NONE_ROOM} head={unchanged} />
      </label>
      <div className="grid2">
        <label>
          {t('detail.status')}
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            {unchanged}
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s === 'none' ? t('bulkEdit.noStatus') : t(`status.${kindForLabels}.${s}`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('rating')}
          <select value={rating} onChange={(e) => setRating(e.target.value)}>
            {unchanged}
            <option value="0">{t('bulkEdit.noRating')}</option>
            {[1, 2, 3, 4, 5].map((r) => (
              <option key={r} value={r}>
                {'★'.repeat(r)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('field.kind')}
          <select value={kind} onChange={(e) => setKind(e.target.value)}>
            {unchanged}
            {KINDS.map((k) => (
              <option key={k} value={k}>
                {t(`kind.${k}`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('field.format')}
          <select value={format} onChange={(e) => setFormat(e.target.value)}>
            {unchanged}
            {FORMATS.map((f) => (
              <option key={f} value={f}>
                {t(`format.${f}`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('scope.wish')}
          <select value={owned} onChange={(e) => setOwned(e.target.value)}>
            {unchanged}
            <option value="yes">{t('bulkEdit.owned')}</option>
            <option value="no">{t('scope.wish')}</option>
          </select>
        </label>
        <label>
          👍 {t('detail.recommend')}
          <select value={recommend} onChange={(e) => setRecommend(e.target.value)}>
            {yesNo}
          </select>
        </label>
        <label>
          {t('bulkEdit.addTag')}
          <input value={addTag} onChange={(e) => setAddTag(e.target.value)} placeholder={t('form.tagsHint')} />
        </label>
        {allTags.length > 0 && (
          <label>
            {t('bulkEdit.removeTag')}
            <select value={removeTag} onChange={(e) => setRemoveTag(e.target.value)}>
              <option value="">–</option>
              {allTags.map((tag) => (
                <option key={tag} value={tag}>
                  {tag}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>
      <label className="toggle">
        <input type="checkbox" checked={checked} onChange={(e) => setChecked(e.target.checked)} />
        {t('bulkEdit.checked')}
      </label>
    </Sheet>
  )
}
