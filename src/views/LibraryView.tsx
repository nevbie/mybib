import { useMemo, useState } from 'react'
import { ItemRow } from '../components/ItemRow'
import { useRooms, useShelves } from '../components/usePlaces'
import { useLang } from '../i18n'
import { applyFilters, EMPTY_FILTERS, openLoan, sortItems, type Filters, type SortKey } from '../logic/items'
import { useStore } from '../store'
import { FORMATS, KINDS, STATUSES } from '../types'
import { useUI } from '../ui'

const SCOPES: Filters['scope'][] = ['all', 'wish', 'lent', 'recommend', 'check']
const SORTS: SortKey[] = ['title', 'creator', 'added', 'rating', 'year', 'place']
/** render in pages so a 2 000-item library stays smooth */
const PAGE = 120

export function LibraryView() {
  const { t, lang } = useLang()
  const { items, ready } = useStore()
  const ui = useUI()
  const f = ui.filters
  const set = (patch: Partial<Filters>) => ui.setFilters({ ...f, ...patch })
  const [more, setMore] = useState(false)
  const [limit, setLimit] = useState(PAGE)
  const rooms = useRooms()
  const shelves = useShelves(f.room === 'all' ? undefined : f.room)

  const list = useMemo(() => sortItems(applyFilters(items, f), ui.sort, lang), [items, f, ui.sort, lang])
  const counts = useMemo(
    () => ({
      wish: items.filter((i) => !i.owned).length,
      lent: items.filter((i) => openLoan(i)).length,
      recommend: items.filter((i) => i.recommend).length,
      check: items.filter((i) => i.needsCheck).length,
    }),
    [items],
  )
  const extraActive = [f.status !== 'all', f.format !== 'all', f.room !== 'all', f.shelf !== 'all', f.minRating > 0].filter(Boolean).length

  return (
    <div className="page">
      <header className="page-head">
        <h1>
          mybib <span className="muted count">{items.length}</span>
        </h1>
      </header>

      <input className="search" type="search" placeholder={t('lib.search')} value={f.q} onChange={(e) => (set({ q: e.target.value }), setLimit(PAGE))} aria-label={t('lib.search')} />

      <div className="chips" role="group" aria-label={t('lib.kind')}>
        <button className={f.kind === 'all' ? 'chip on' : 'chip'} onClick={() => set({ kind: 'all' })}>
          {t('kind.all')}
        </button>
        {KINDS.map((k) => (
          <button key={k} className={f.kind === k ? 'chip on' : 'chip'} onClick={() => set({ kind: f.kind === k ? 'all' : k })}>
            {t(`kind.${k}.pl`)}
          </button>
        ))}
      </div>
      <div className="chips" role="group" aria-label={t('lib.scope')}>
        {SCOPES.filter((s) => s === 'all' || counts[s as keyof typeof counts] > 0 || f.scope === s).map((s) => (
          <button key={s} className={f.scope === s ? 'chip on' : 'chip'} onClick={() => set({ scope: f.scope === s ? 'all' : s })}>
            {t(`scope.${s}`)}
            {s !== 'all' && <span className="chip-n">{counts[s as keyof typeof counts]}</span>}
          </button>
        ))}
        <button className={more || extraActive ? 'chip on' : 'chip'} onClick={() => setMore(!more)} aria-expanded={more}>
          ⚙︎ {t('lib.more')}
          {extraActive > 0 && <span className="chip-n">{extraActive}</span>}
        </button>
      </div>

      {more && (
        <div className="card filters">
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
            {t('field.format')}
            <select value={f.format} onChange={(e) => set({ format: e.target.value as Filters['format'] })}>
              <option value="all">{t('any')}</option>
              {FORMATS.map((s) => (
                <option key={s} value={s}>
                  {t(`format.${s}`)}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t('field.room')}
            <select value={f.room} onChange={(e) => set({ room: e.target.value, shelf: 'all' })}>
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
            {t('field.shelf')}
            <select value={f.shelf} onChange={(e) => set({ shelf: e.target.value })}>
              <option value="all">{t('any')}</option>
              {shelves.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t('lib.minRating')}
            <select value={f.minRating} onChange={(e) => set({ minRating: Number(e.target.value) })}>
              <option value={0}>{t('any')}</option>
              {[1, 2, 3, 4, 5].map((n) => (
                <option key={n} value={n}>
                  {'★'.repeat(n)}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t('lib.sort')}
            <select value={ui.sort} onChange={(e) => ui.setSort(e.target.value as SortKey)}>
              {SORTS.map((s) => (
                <option key={s} value={s}>
                  {t(`sort.${s}`)}
                </option>
              ))}
            </select>
          </label>
          <button className="btn ghost" onClick={() => ui.setFilters({ ...EMPTY_FILTERS })}>
            {t('lib.reset')}
          </button>
        </div>
      )}

      {ready && items.length === 0 ? (
        <div className="empty">
          <p>{t('lib.empty')}</p>
          <button className="btn primary" onClick={() => ui.go('add')}>
            ➕ {t('nav.add')}
          </button>
        </div>
      ) : (
        <>
          {list.length !== items.length && <p className="muted small">{t('lib.shown', { n: list.length })}</p>}
          <div className="list">
            {list.slice(0, limit).map((i) => (
              <ItemRow key={i.id} item={i} onClick={() => ui.openItem(i.id)} />
            ))}
          </div>
          {list.length > limit && (
            <button className="btn ghost wide" onClick={() => setLimit(limit + PAGE)}>
              {t('lib.showMore', { n: list.length - limit })}
            </button>
          )}
          {list.length === 0 && <p className="empty muted">{t('lib.noMatch')}</p>}
        </>
      )}
    </div>
  )
}
