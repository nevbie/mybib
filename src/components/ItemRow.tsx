import { useLang } from '../i18n'
import { openLoan } from '../logic/items'
import type { Item } from '../types'
import { Cover, Stars } from './bits'

export function ItemRow({ item, onClick }: { item: Item; onClick(): void }) {
  const { t } = useLang()
  const loan = openLoan(item)
  const place = [item.room, item.shelf].filter(Boolean).join(' · ')
  return (
    <button className="item-row" onClick={onClick}>
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
