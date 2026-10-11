import { useMemo, useState } from 'react'
import { CategorySelect } from '../components/CategorySelect'
import { ItemRow } from '../components/ItemRow'
import { Sheet } from '../components/Sheet'
import { useRooms } from '../components/usePlaces'
import { useLang } from '../i18n'
import { applyFilters, duplicateGroups, EMPTY_FILTERS, groupKey, mergeGroup, type Filters } from '../logic/items'
import { useStore } from '../store'
import { KINDS, STATUSES, type Item } from '../types'
import { useUI } from '../ui'

const SCOPES: Filters['scope'][] = ['all', 'owned', 'wish', 'lent', 'recommend', 'check']

/** Tidy up: find and merge duplicates, edit or delete many entries chosen by filter. */
export function TidySheet() {
  const { t } = useLang()
  const ui = useUI()
  const { items, settings, updateSettings, applyMerges, removeItems } = useStore()
  const noCover = useMemo(() => items.filter((i) => !i.coverData && !i.coverUrl).length, [items])
  const groups = useMemo(() => duplicateGroups(items, settings.dupIgnore), [items, settings.dupIgnore])

  const mergeAll = () => {
    const merges = groups.map(mergeGroup)
    const m = merges.reduce((n, x) => n + x.remove.length, 0)
    if (confirm(t('tidy.mergeAllConfirm', { n: groups.length, m }))) applyMerges(merges)
  }
  const ignore = (g: Item[]) => updateSettings({ dupIgnore: [...settings.dupIgnore, groupKey(g)] })

  return (
    <Sheet title={`🧹 ${t('tidy.title')}`} onClose={ui.close}>
      <h2>{t('tidy.dups')}</h2>
      {groups.length === 0 ? (
        <p className="muted">{t('tidy.dupsNone')}</p>
      ) : (
        <>
          <p className="muted small">{t('tidy.dupsIntro')}</p>
          {groups.length > 1 && (
            <button className="btn primary wide" onClick={mergeAll}>
              🔗 {t('tidy.mergeAll', { n: groups.length })}
            </button>
          )}
          {groups.map((g) => (
            <DupGroup key={groupKey(g)} group={g} onMerge={() => applyMerges([mergeGroup(g)])} onDelete={(ids) => removeItems(ids)} onIgnore={() => ignore(g)} />
          ))}
        </>
      )}
      {settings.dupIgnore.length > 0 && (
        <p className="muted small">
          {t('tidy.ignored', { n: settings.dupIgnore.length })}{' '}
          <button className="link small" onClick={() => updateSettings({ dupIgnore: [] })}>
            {t('tidy.resetIgnored')}
          </button>
        </p>
      )}
      <h2>{t('covers.title')}</h2>
      <p className="muted small">{t('covers.card', { n: noCover })}</p>
      <div className="row gap wrap">
        <button className="btn" onClick={() => ui.open({ type: 'covers' })}>
          📷 {t('covers.title')}
        </button>
        <button className="btn" onClick={() => ui.open({ type: 'rotate' })}>
          ⟳ {t('rotate.title')}
        </button>
      </div>
      <BulkByFilter />
    </Sheet>
  )
}

function DupGroup({ group, onMerge, onDelete, onIgnore }: { group: Item[]; onMerge(): void; onDelete(ids: string[]): void; onIgnore(): void }) {
  const { t } = useLang()
  const ui = useUI()
  const [sel, setSel] = useState<Set<string>>(new Set())
  const keepId = useMemo(() => mergeGroup(group).keep.id, [group])
  const toggle = (id: string) =>
    setSel((s) => {
      const n = new Set(s)
      if (n.has(id)) n.delete(id)
      else n.add(id)
      return n
    })
  const picked = group.filter((i) => sel.has(i.id)).map((i) => i.id)
  const del = () => {
    if (confirm(t('bulkEdit.deleteConfirm', { n: picked.length }))) onDelete(picked)
  }
  return (
    <section className="card dup-group">
      <div className="list">
        {group.map((i) => (
          <div key={i.id} className="dup-row">
            <ItemRow item={i} selected={sel.has(i.id)} onClick={() => toggle(i.id)} />
            <span className="row center between">
              {i.id === keepId ? <span className="badge badge-rec">✓ {t('tidy.keep')}</span> : <span />}
              <button className="link small" onClick={() => ui.openItem(i.id)}>
                {t('tidy.open')}
              </button>
            </span>
          </div>
        ))}
      </div>
      <div className="row gap wrap">
        <button className="btn small primary" onClick={onMerge}>
          🔗 {t('tidy.merge')}
        </button>
        <button className="btn small danger ghost" onClick={del} disabled={!picked.length || picked.length === group.length}>
          🗑 {t('tidy.deleteSel', { n: picked.length })}
        </button>
        <button className="btn small ghost" onClick={onIgnore}>
          {t('tidy.notDup')}
        </button>
      </div>
    </section>
  )
}

/** Choose entries by kind, selection, status, room and category – then edit, delete or show them. */
function BulkByFilter() {
  const { t } = useLang()
  const ui = useUI()
  const { items, removeItems } = useStore()
  const rooms = useRooms()
  const [f, setF] = useState<Filters>(EMPTY_FILTERS)
  const set = (patch: Partial<Filters>) => setF({ ...f, ...patch })
  const ids = useMemo(() => applyFilters(items, f).map((i) => i.id), [items, f])
  const n = ids.length

  const del = () => {
    if (confirm(t('bulkEdit.deleteConfirm', { n }))) removeItems(ids)
  }
  const show = () => {
    ui.setFilters(f)
    ui.go('library')
  }

  return (
    <>
      <h2>{t('tidy.bulk')}</h2>
      <p className="muted small">{t('tidy.bulkIntro')}</p>
      <div className="card filters">
        <label>
          {t('lib.kind')}
          <select value={f.kind} onChange={(e) => set({ kind: e.target.value as Filters['kind'] })}>
            <option value="all">{t('kind.all')}</option>
            {KINDS.map((k) => (
              <option key={k} value={k}>
                {t(`kind.${k}.pl`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('lib.scope')}
          <select value={f.scope} onChange={(e) => set({ scope: e.target.value as Filters['scope'] })}>
            {SCOPES.map((s) => (
              <option key={s} value={s}>
                {t(`scope.${s}`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('lib.status')}
          <select value={f.status} onChange={(e) => set({ status: e.target.value as Filters['status'] })}>
            <option value="all">{t('any')}</option>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {t(`status.${f.kind === 'all' ? 'book' : f.kind}.${s}`)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('field.room')}
          <select value={f.room} onChange={(e) => set({ room: e.target.value })}>
            <option value="all">{t('any')}</option>
            {rooms.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
            <option value="">{t('places.none')}</option>
          </select>
        </label>
        <label>
          {t('field.category')}
          <CategorySelect value={f.category} onChange={(category) => set({ category })} head={<option value="all">{t('any')}</option>} />
        </label>
        <label>
          {t('lib.search')}
          <input type="search" value={f.q} onChange={(e) => set({ q: e.target.value })} />
        </label>
      </div>
      <p>
        <strong>{t('tidy.match', { n })}</strong>
      </p>
      <div className="row gap wrap">
        <button className="btn primary" disabled={!n} onClick={() => ui.open({ type: 'bulkEdit', ids })}>
          ✎ {t('sel.edit')}
        </button>
        <button className="btn danger ghost" disabled={!n} onClick={del}>
          🗑 {t('detail.delete')}
        </button>
        <button className="btn ghost" disabled={!n} onClick={show}>
          {t('tidy.show')}
        </button>
      </div>
    </>
  )
}
