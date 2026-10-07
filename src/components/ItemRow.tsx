import { useLang } from '../i18n'
import { openLoan } from '../logic/items'
import type { Item } from '../types'
import { Cover, Stars } from './bits'

export function ItemRow({ item, onClick, selected }: { item: Item; onClick(): void; /** set in selection mode */ selected?: boolean }) {
  const { t } = useLang()
  const loan = openLoan(item)
  const place = item.room
  return (
    <button className={selected ? 'item-row selected' : 'item-row'} onClick={onClick} aria-pressed={selected}>
      {selected !== undefined && <input type="checkbox" checked={selected} readOnly tabIndex={-1} aria-hidden className="item-check" />}
      <Cover item={item} />
      <span className="item-row-main">
        <span className="item-row-title">
          {item.title}
          {item.volume && <span className="muted"> · {item.volume}</span>}
        </span>
        {item.creators.length > 0 && <span className="item-row-sub">{item.creators.join(', ')}</span>}
        <span className="item-row-meta">
          <Stars value={item.rating} size="sm" />
          {item.status !== 'none' && <span className={`badge badge-${item.status}`}>{t(`status.${item.kind}.${item.status}`)}</span>}
          {item.format !== 'physical' && <span className="badge">{t(`format.${item.format}`)}</span>}
          {!item.owned && <span className="badge badge-wish">{t('scope.wish')}</span>}
          {item.recommend && <span className="badge badge-rec">👍</span>}
          {loan && <span className="badge badge-lent">↗ {loan.to}</span>}
          {item.needsCheck && <span className="badge badge-check">?</span>}
          {place && <span className="item-row-place">{place}</span>}
        </span>
      </span>
    </button>
  )
}
