import { useMemo } from 'react'
import { useCategories, useRooms } from '../components/usePlaces'
import { categoryLabel } from '../logic/categories'
import { useLang } from '../i18n'
import { EMPTY_FILTERS, openLoan, summarizePlaces } from '../logic/items'
import { useStore } from '../store'
import { DEFAULT_ROOMS, KINDS } from '../types'
import { useUI } from '../ui'

export function PlacesView() {
  const { t, lang, pick } = useLang()
  const ui = useUI()
  const { items, settings, moveRoom, updateSettings } = useStore()
  const rooms = useRooms()
  const summary = useMemo(() => summarizePlaces(items, lang), [items, lang])
  const byRoom = new Map(summary.map((s) => [s.room, s]))
  const unplaced = byRoom.get('')

  const show = (room: string) => {
    ui.setFilters({ ...EMPTY_FILTERS, room, scope: 'owned', format: 'physical' })
    ui.setSort('place')
    ui.go('library')
  }

  // only rooms set up by hand are stored; rooms that just come from items appear and vanish with them
  const configured = settings.rooms.length ? settings.rooms : DEFAULT_ROOMS.map(pick)
  const saveRooms = (list: string[]) => updateSettings({ rooms: list.filter((r, i, a) => r && a.indexOf(r) === i) })

  const addRoom = () => {
    const name = prompt(t('places.newRoom'))?.trim()
    if (name && !rooms.includes(name)) saveRooms([...configured, name])
  }
  const renameRoom = (room: string) => {
    const name = prompt(t('places.renameRoom', { room }), room)?.trim()
    if (!name || name === room) return
    if (rooms.includes(name) && !confirm(t('places.mergeConfirm', { room, name }))) return
    moveRoom(room, name)
    saveRooms(configured.includes(room) ? configured.map((r) => (r === room ? name : r)) : configured)
  }
  const removeRoom = (room: string) => {
    const n = byRoom.get(room)?.count ?? 0
    if (n && !confirm(t('places.removeRoomConfirm', { room, n }))) return
    if (n) moveRoom(room, '')
    saveRooms(configured.filter((r) => r !== room))
  }

  const categories = useCategories()
  const catStats = useMemo(() => {
    const count = new Map<string, number>()
    for (const i of items) count.set(i.category ?? '', (count.get(i.category ?? '') ?? 0) + 1)
    if (count.size === 1 && count.has('')) return []
    return [...categories, ''].filter((c) => count.get(c)).map((c) => [c, count.get(c)!] as const)
  }, [items, categories])
  const showCategory = (category: string) => {
    ui.setFilters({ ...EMPTY_FILTERS, category })
    ui.go('library')
  }

  const stats = useMemo(() => {
    const owned = items.filter((i) => i.owned)
    return {
      kinds: KINDS.map((k) => [k, owned.filter((i) => i.kind === k).length] as const).filter(([, n]) => n),
      ebooks: owned.filter((i) => i.format !== 'physical').length,
      done: items.filter((i) => i.status === 'done').length,
      want: items.filter((i) => i.status === 'want').length,
      lent: items.filter((i) => openLoan(i)).length,
      wish: items.length - owned.length,
    }
  }, [items])

  return (
    <div className="page">
      <h1>{t('nav.places')}</h1>
      <div className="stats">
        {stats.kinds.map(([k, n]) => (
          <div key={k} className="stat">
            <strong>{n}</strong>
            <span>{t(`kind.${k}.pl`)}</span>
          </div>
        ))}
        {stats.ebooks > 0 && (
          <div className="stat">
            <strong>{stats.ebooks}</strong>
            <span>{t('places.digital')}</span>
          </div>
        )}
        <div className="stat">
          <strong>{stats.done}</strong>
          <span>{t('places.done')}</span>
        </div>
        <div className="stat">
          <strong>{stats.want}</strong>
          <span>{t('places.want')}</span>
        </div>
        {stats.lent > 0 && (
          <div className="stat">
            <strong>{stats.lent}</strong>
            <span>{t('scope.lent')}</span>
          </div>
        )}
        {stats.wish > 0 && (
          <div className="stat">
            <strong>{stats.wish}</strong>
            <span>{t('scope.wish')}</span>
          </div>
        )}
      </div>

      {catStats.length > 0 && (
        <>
          <h2>{t('field.category')}</h2>
          <div className="chips wrap">
            {catStats.map(([c, n]) => (
              <button key={c} className="chip" onClick={() => showCategory(c)}>
                {c ? categoryLabel(c, lang) : t('cat.none')} <span className="chip-n">{n}</span>
              </button>
            ))}
          </div>
          <h2>{t('nav.places')}</h2>
        </>
      )}
      {rooms.map((room) => {
        const s = byRoom.get(room)
        return (
          <section key={room} className="card room">
            <div className="row between center">
              <button className="link room-name" onClick={() => show(room)}>
                🏠 {room} <span className="muted">({s?.count ?? 0})</span>
              </button>
              <span className="row">
                <button className="icon-btn" onClick={() => renameRoom(room)} aria-label={t('places.rename')}>
                  ✎
                </button>
                <button className="icon-btn" onClick={() => removeRoom(room)} aria-label={t('places.remove')}>
                  ✕
                </button>
              </span>
            </div>
          </section>
        )
      })}
      {unplaced && (
        <section className="card room">
          <button className="link room-name" onClick={() => show('')}>
            ❔ {t('places.none')} <span className="muted">({unplaced.count})</span>
          </button>
        </section>
      )}
      <button className="btn" onClick={addRoom}>
        ＋ {t('places.addRoom')}
      </button>
      <p className="muted small">{t('places.tip')}</p>
    </div>
  )
}
