import { useRef, useState } from 'react'
import { Cover, Segmented, Suggest } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useRooms, useShelves } from '../components/usePlaces'
import { useLang } from '../i18n'
import { coverFromPhoto } from '../logic/image'
import { findDuplicate } from '../logic/items'
import { classifyCode } from '../logic/isbn'
import { enrichPatch } from '../logic/lookup'
import { useStore } from '../store'
import { FORMATS, KINDS, STATUSES, type Item, type ItemDraft, type Kind } from '../types'
import { useUI } from '../ui'

type Draft = Partial<Item> & { title: string; kind: Kind }

const numOrUndef = (s: string) => (s.trim() && Number.isFinite(Number(s)) ? Number(s) : undefined)

export function ItemForm({ id, draft: initial }: { id?: string; draft?: ItemDraft }) {
  const { t } = useLang()
  const ui = useUI()
  const { byId, items, settings, addItems, updateItem, updateSettings } = useStore()
  const existing = id ? byId.get(id) : undefined
  const [d, setD] = useState<Draft>(() => ({
    kind: 'book',
    format: 'physical',
    owned: true,
    status: 'none',
    room: settings.lastRoom || undefined,
    shelf: settings.lastShelf || undefined,
    ...(existing ?? initial),
    title: existing?.title ?? initial?.title ?? '',
  }))
  const [creators, setCreators] = useState((d.creators ?? []).join(', '))
  const [tags, setTags] = useState((d.tags ?? []).join(', '))
  const rooms = useRooms()
  const shelves = useShelves(d.room)
  const fileRef = useRef<HTMLInputElement>(null)
  const set = (patch: Partial<Draft>) => setD((x) => ({ ...x, ...patch }))
  const txt = (k: keyof Item) => (d[k] as string | undefined) ?? ''
  const num = (k: keyof Item) => (d[k] === undefined ? '' : String(d[k]))

  const split = (s: string) =>
    s
      .split(/[,;]/)
      .map((x) => x.trim())
      .filter(Boolean)
  const full = (): Draft => ({ ...d, title: d.title.trim(), creators: split(creators), tags: split(tags) })
  const dup = !existing && d.title.trim() ? findDuplicate(items, full()) : undefined

  const fillOnline = async () => {
    const c = await ui.pickCandidate(d.kind, d.title, split(creators)[0] ?? '')
    if (!c) return
    const cur = full()
    const patch = d.title.trim() ? enrichPatch(cur, c) : { ...c }
    if (!d.title.trim()) set({ title: c.title })
    if (!split(creators).length && c.creators?.length) setCreators(c.creators.join(', '))
    set({ ...patch, kind: d.kind, source: existing ? d.source : 'search' })
  }

  const onPhoto = async (f?: File) => {
    if (!f) return
    set({ coverData: await coverFromPhoto(f) })
  }

  const save = async () => {
    const v = full()
    if (!v.title) return
    if (v.isbn) {
      const c = classifyCode(v.isbn)
      if (c.type !== 'invalid') v.isbn = c.code
    }
    if (existing) {
      updateItem(existing.id, v)
    } else {
      await addItems([v])
      updateSettings({ lastRoom: v.room ?? '', lastShelf: v.shelf ?? '' })
    }
    ui.close()
  }

  const isBook = d.kind === 'book'
  return (
    <Sheet
      title={existing ? t('form.edit') : t('form.new')}
      onClose={ui.close}
      footer={
        <button className="btn primary wide" onClick={save} disabled={!d.title.trim()}>
          {t('save')}
        </button>
      }
    >
      <Segmented<Kind> value={d.kind} label={t('field.kind')} onChange={(kind) => set({ kind, format: kind === 'book' ? d.format : 'physical' })} options={KINDS.map((k) => ({ value: k, label: t(`kind.${k}`) }))} />

      <div className="form-cover">
        <Cover item={{ ...d, title: d.title || '?' }} size="lg" />
        <div className="col gap">
          <button className="btn small" onClick={() => fileRef.current?.click()}>
            📷 {t('form.coverPhoto')}
          </button>
          {(d.coverData || d.coverUrl) && (
            <button className="btn small ghost" onClick={() => set({ coverData: undefined, coverUrl: undefined })}>
              {t('form.coverRemove')}
            </button>
          )}
          <button className="btn small" onClick={fillOnline} disabled={d.kind === 'game'}>
            🔎 {t('form.fillOnline')}
          </button>
          <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={(e) => onPhoto(e.target.files?.[0])} />
        </div>
      </div>

      <label>
        {t('field.title')} *
        <input value={d.title} onChange={(e) => set({ title: e.target.value })} autoFocus={!existing && !initial} />
      </label>
      {dup && (
        <p className="notice small">
          {t('form.duplicate')}{' '}
          <button className="link" onClick={() => ui.openItem(dup.id)}>
            {dup.title}
          </button>
        </p>
      )}
      <label>
        {t(`creator.${d.kind}`)}
        <input value={creators} onChange={(e) => setCreators(e.target.value)} placeholder={t('form.commaHint')} />
      </label>
      {isBook && (
        <label>
          {t('field.subtitle')}
          <input value={txt('subtitle')} onChange={(e) => set({ subtitle: e.target.value })} />
        </label>
      )}
      <div className="grid2">
        <label>
          {t('field.seriesOnly')}
          <input value={txt('series')} onChange={(e) => set({ series: e.target.value })} />
        </label>
        <label>
          {t('field.volume')}
          <input value={txt('volume')} onChange={(e) => set({ volume: e.target.value })} />
        </label>
        <label>
          {t(d.kind === 'cd' ? 'field.label' : 'field.publisher')}
          <input value={txt('publisher')} onChange={(e) => set({ publisher: e.target.value })} />
        </label>
        <label>
          {t('field.year')}
          <input inputMode="numeric" value={num('year')} onChange={(e) => set({ year: numOrUndef(e.target.value) })} />
        </label>
        <label>
          {t(isBook ? 'field.isbn' : 'field.ean')}
          <input inputMode="numeric" value={txt('isbn')} onChange={(e) => set({ isbn: e.target.value })} />
        </label>
        <label>
          {t('field.language')}
          <input value={txt('language')} onChange={(e) => set({ language: e.target.value })} placeholder="de, en, zh …" />
        </label>
        {isBook && (
          <label>
            {t('field.pages')}
            <input inputMode="numeric" value={num('pages')} onChange={(e) => set({ pages: numOrUndef(e.target.value) })} />
          </label>
        )}
        <label>
          {t('field.ageFrom')}
          <input inputMode="numeric" value={num('ageFrom')} onChange={(e) => set({ ageFrom: numOrUndef(e.target.value) })} />
        </label>
        {d.kind === 'game' && (
          <>
            <label>
              {t('field.playersMin')}
              <input inputMode="numeric" value={num('playersMin')} onChange={(e) => set({ playersMin: numOrUndef(e.target.value) })} />
            </label>
            <label>
              {t('field.playersMax')}
              <input inputMode="numeric" value={num('playersMax')} onChange={(e) => set({ playersMax: numOrUndef(e.target.value) })} />
            </label>
            <label>
              {t('field.playMinutes')}
              <input inputMode="numeric" value={num('playMinutes')} onChange={(e) => set({ playMinutes: numOrUndef(e.target.value) })} />
            </label>
          </>
        )}
      </div>

      {isBook && (
        <label>
          {t('field.format')}
          <Segmented value={d.format ?? 'physical'} label={t('field.format')} onChange={(format) => set({ format })} options={FORMATS.map((f) => ({ value: f, label: t(`format.${f}`) }))} />
        </label>
      )}
      <label>
        {t('detail.status')}
        <select value={d.status} onChange={(e) => set({ status: e.target.value as Item['status'] })}>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {t(`status.${d.kind}.${s}`)}
            </option>
          ))}
        </select>
      </label>
      <label className="toggle">
        <input type="checkbox" checked={d.owned === false} onChange={(e) => set({ owned: !e.target.checked })} />
        {t('detail.wishlist')}
      </label>

      {d.owned !== false && (d.format ?? 'physical') === 'physical' && (
        <div className="grid2">
          <label>
            {t('field.room')}
            <Suggest id="f-rooms" value={txt('room')} options={rooms} onChange={(room) => set({ room })} />
          </label>
          <label>
            {t('field.shelf')}
            <Suggest id="f-shelves" value={txt('shelf')} options={shelves} onChange={(shelf) => set({ shelf })} />
          </label>
        </div>
      )}
      <label>
        {t('field.tags')}
        <input value={tags} onChange={(e) => setTags(e.target.value)} placeholder={t('form.tagsHint')} />
      </label>
      <label>
        {t('field.notes')}
        <textarea rows={3} value={txt('notes')} onChange={(e) => set({ notes: e.target.value })} />
      </label>
    </Sheet>
  )
}
