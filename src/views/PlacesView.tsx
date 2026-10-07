import { useMemo } from 'react'
import { useRooms } from '../components/usePlaces'
import { useLang } from '../i18n'
import { EMPTY_FILTERS, openLoan, summarizePlaces } from '../logic/items'
import { useStore } from '../store'
import { KINDS } from '../types'
import { useUI } from '../ui'

export function PlacesView() {
  const { t, lang } = useLang()
  const ui = useUI()
  const { items, settings, movePlace, updateSettings } = useStore()
  const rooms = useRooms()
  const summary = useMemo(() => summarizePlaces(items, lang), [items, lang])
  const byRoom = new Map(summary.map((s) => [s.room, s]))
  const unplaced = byRoom.get('')

  const show = (room: string, shelf?: string) => {
    ui.setFilters({ ...EMPTY_FILTERS, room, shelf: shelf ?? 'all', scope: 'owned', format: 'physical' })
    ui.setSort('place')
    ui.go('library')
  }

  const saveRooms = (list: string[]) => updateSettings({ rooms: list })

  const addRoom = () => {
    const name = prompt(t('places.newRoom'))?.trim()
    if (name && !rooms.includes(name)) saveRooms([...rooms, name])
  }
  const renameRoom = (room: string) => {
    const name = prompt(t('places.renameRoom', { room }), room)?.trim()
    if (!name || name === room) return
    movePlace({ room }, { room: name })
    saveRooms(rooms.map((r) => (r === room ? name : r)).filter((r, i, a) => a.indexOf(r) === i))
  }
  const removeRoom = (room: string) => {
    const n = byRoom.get(room)?.count ?? 0
    if (n && !confirm(t('places.removeRoomConfirm', { room, n }))) return
    if (n) movePlace({ room }, { room: '' })
    saveRooms(rooms.filter((r) => r !== room))
  }
  const editShelf = (room: string, shelf: string) => {
    const name = prompt(t('places.renameShelf', { shelf: shelf || '–' }), shelf)
    if (name === null) return
    const target = prompt(t('places.moveShelf'), room)
    if (target === null) return
    movePlace({ room, shelf }, { room: target.trim(), shelf: name.trim() })
    if (target.trim() && !rooms.includes(target.trim())) saveRooms([...rooms, target.trim()])
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
            {s && (
              <ul className="shelves">
                {s.shelves.map((sh) => (
                  <li key={sh.shelf}>
                    <button className="link" onClick={() => show(room, sh.shelf)}>
                      {sh.shelf || t('places.noShelf')} <span className="muted">({sh.count})</span>
                    </button>
                    <button className="icon-btn small" onClick={() => editShelf(room, sh.shelf)} aria-label={t('places.rename')}>
                      ✎
                    </button>
                  </li>
                ))}
              </ul>
            )}
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
      {settings.rooms.length === 0 && <p className="muted small">{t('places.tip')}</p>}
    </div>
  )
}
