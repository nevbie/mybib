import { useRef } from 'react'
import { useLang } from '../i18n'
import { categoryLabel } from '../logic/categories'
import { openLoan } from '../logic/items'
import type { Item } from '../types'
import type { ViewMode } from '../ui'
import { Cover, Stars } from './bits'

/** "Lucky Luke 22", else the subtitle, else the volume – shown under the title instead of a bare number. */
export function seriesLine(i: Item): string {
  if (i.series) return [i.series, i.volume].filter(Boolean).join(' ')
  return i.subtitle ?? i.volume ?? ''
}

/** Press and hold (≈ ½ s) – starts the selection in the library. */
function useLongPress(onLongPress?: () => void) {
  const timer = useRef<number | undefined>(undefined)
  const fired = useRef(false)
  if (!onLongPress) return {}
  const clear = () => window.clearTimeout(timer.current)
  return {
    onPointerDown: () => {
      fired.current = false
      timer.current = window.setTimeout(() => {
        fired.current = true
        onLongPress()
      }, 500)
    },
    onPointerUp: clear,
    onPointerLeave: clear,
    onPointerCancel: clear,
    onContextMenu: (e: React.MouseEvent) => e.preventDefault(),
    /** swallow the click that ends a long press */
    onClickCapture: (e: React.MouseEvent) => {
      if (fired.current) {
        e.stopPropagation()
        fired.current = false
      }
    },
  }
}

export function ItemRow({ item, onClick, onLongPress, selected, view = 'list' }: { item: Item; onClick(): void; onLongPress?(): void; /** set in selection mode */ selected?: boolean; view?: ViewMode }) {
  const { t, lang } = useLang()
  const press = useLongPress(onLongPress)
  const loan = openLoan(item)
  const place = item.room
  const sub = seriesLine(item)
  const check = selected !== undefined && <input type="checkbox" checked={selected} readOnly tabIndex={-1} aria-hidden className="item-check" />
  const cls = (base: string) => (selected ? `${base} selected` : base)

  if (view === 'grid') {
    return (
      <button className={cls('item-tile')} onClick={onClick} aria-pressed={selected} {...press}>
        <span className="item-tile-cover">
          <Cover item={item} size="lg" />
          {check}
          {item.needsCheck && <span className="badge badge-check item-tile-flag">?</span>}
        </span>
        <span className="item-tile-title">{item.title}</span>
        {sub && <span className="item-tile-sub">{sub}</span>}
      </button>
    )
  }

  if (view === 'compact') {
    return (
      <button className={cls('item-row compact')} onClick={onClick} aria-pressed={selected} {...press}>
        {check}
        <Cover item={item} />
        <span className="item-row-main">
          <span className="item-row-title">{item.title}</span>
          <span className="item-row-sub">{[sub, item.creators.join(', ')].filter(Boolean).join(' · ')}</span>
        </span>
        <span className="item-row-flags">
          {item.status !== 'none' && <span className={`badge badge-${item.status}`}>{t(`status.${item.kind}.${item.status}`)}</span>}
          {loan && <span className="badge badge-lent">↗</span>}
          {item.needsCheck && <span className="badge badge-check">?</span>}
        </span>
      </button>
    )
  }

  return (
    <button className={cls('item-row')} onClick={onClick} aria-pressed={selected} {...press}>
      {check}
      <Cover item={item} />
      <span className="item-row-main">
        <span className="item-row-title">{item.title}</span>
        {sub && <span className="item-row-series">{sub}</span>}
        {item.creators.length > 0 && <span className="item-row-sub">{item.creators.join(', ')}</span>}
        <span className="item-row-meta">
          <Stars value={item.rating} size="sm" />
          {item.status !== 'none' && <span className={`badge badge-${item.status}`}>{t(`status.${item.kind}.${item.status}`)}</span>}
          {item.format !== 'physical' && <span className="badge">{t(`format.${item.format}`)}</span>}
          {!item.owned && <span className="badge badge-wish">{t('scope.wish')}</span>}
          {item.category && <span className="badge badge-cat">{categoryLabel(item.category, lang)}</span>}
          {item.recommend && <span className="badge badge-rec">👍</span>}
          {loan && <span className="badge badge-lent">↗ {loan.to}</span>}
          {item.needsCheck && <span className="badge badge-check">?</span>}
          {place && <span className="item-row-place">{place}</span>}
        </span>
      </span>
    </button>
  )
}
