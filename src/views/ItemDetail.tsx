import { useState } from 'react'
import { Cover, KIND_ICON, Segmented, Stars, Suggest, TextField } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useRooms, useShelves } from '../components/usePlaces'
import { useLang } from '../i18n'
import { knownPeople, openLoan, today } from '../logic/items'
import { enrichPatch } from '../logic/lookup'
import { useStore } from '../store'
import { STATUSES, type Item, type Status } from '../types'
import { useUI } from '../ui'

export function shareText(item: Item, t: (k: string, v?: Record<string, string | number>) => string): string {
  const lines = [`${item.title}${item.creators.length ? ' – ' + item.creators.join(', ') : ''}`]
  if (item.rating) lines.push('★'.repeat(item.rating) + '☆'.repeat(5 - item.rating))
  if (item.notes) lines.push(item.notes)
  if (item.recommend) lines.push(t('share.recommend'))
  return lines.join('\n')
}

export function shareUrl(item: Item): string | undefined {
  if (!item.isbn) return undefined
  if (item.kind === 'book') return `https://openlibrary.org/isbn/${item.isbn}`
  if (item.kind === 'cd') return `https://musicbrainz.org/search?type=release&query=barcode:${item.isbn}`
  return undefined
}

export function ItemDetail({ id }: { id: string }) {
  const { t, lang } = useLang()
  const ui = useUI()
  const { byId, items, updateItem, removeItems } = useStore()
  const item = byId.get(id)
  const rooms = useRooms()
  const shelves = useShelves(item?.room)
  const [lendTo, setLendTo] = useState('')
  const [lending, setLending] = useState(false)
  const [moreInfo, setMoreInfo] = useState(false)
  if (!item) return null
  const loan = openLoan(item)
  const up = (patch: Partial<Item>) => updateItem(item.id, patch)
  const fmtDate = (d: string) => new Date(d + 'T12:00').toLocaleDateString(lang)

  const share = async () => {
    const text = shareText(item, t)
    const url = shareUrl(item)
    try {
      if (navigator.share) {
        await navigator.share({ title: item.title, text, url })
        return
      }
    } catch (e) {
      if ((e as Error).name === 'AbortError') return
    }
    await navigator.clipboard?.writeText(url ? `${text}\n${url}` : text)
    alert(t('share.copied'))
  }

  const lend = () => {
    const to = lendTo.trim()
    if (!to) return
    up({ loans: [...item.loans, { to, since: today() }] })
    setLendTo('')
    setLending(false)
  }
  const giveBack = () => up({ loans: item.loans.map((l) => (l === loan ? { ...l, returned: today() } : l)) })

  const enrich = async () => {
    const c = await ui.pickCandidate(item.kind, item.title, item.creators[0] ?? '')
    if (c) up({ ...enrichPatch(item, c), needsCheck: undefined })
  }

  const del = () => {
    if (!confirm(t('detail.deleteConfirm', { title: item.title }))) return
    removeItems([item.id])
    ui.close()
  }

  const facts: [string, string | number | undefined][] = [
    [t('field.series'), [item.series, item.volume].filter(Boolean).join(' · ') || undefined],
    [t('field.publisher'), item.publisher],
    [t('field.year'), item.year],
    [t('field.pages'), item.pages],
    [t('field.language'), item.language],
    [t('field.isbn'), item.isbn],
    [t('field.players'), item.playersMin ? `${item.playersMin}${item.playersMax && item.playersMax !== item.playersMin ? '–' + item.playersMax : ''}` : undefined],
    [t('field.playMinutes'), item.playMinutes],
    [t('field.ageFrom'), item.ageFrom ? `${item.ageFrom}+` : undefined],
    [t('field.tags'), item.tags.join(', ') || undefined],
  ]

  return (
    <Sheet
      title={
        <>
          {KIND_ICON[item.kind]} {t(`kind.${item.kind}`)}
        </>
      }
      onClose={ui.close}
      footer={
        <div className="row gap">
          <button className="btn" onClick={share}>
            ↗ {t('detail.share')}
          </button>
          <button className="btn" onClick={() => ui.openForm(item.id)}>
            ✎ {t('detail.edit')}
          </button>
          <button className="btn danger ghost" onClick={del} aria-label={t('detail.delete')}>
            🗑
          </button>
        </div>
      }
    >
      <div className="detail-head">
        <Cover item={item} size="lg" />
        <div>
          <h2 className="detail-title">{item.title}</h2>
          {item.subtitle && <p className="muted">{item.subtitle}</p>}
          {item.creators.length > 0 && <p className="detail-creators">{item.creators.join(', ')}</p>}
          <Stars value={item.rating} onChange={(rating) => up({ rating })} />
        </div>
      </div>

      {item.needsCheck && (
        <div className="notice">
          <p>{t('detail.needsCheck')}</p>
          <div className="row gap">
            <button className="btn small" onClick={() => up({ needsCheck: undefined })}>
              ✓ {t('detail.checked')}
            </button>
            <button className="btn small" onClick={enrich}>
              🔎 {t('detail.enrich')}
            </button>
          </div>
        </div>
      )}

      <h3>{t('detail.status')}</h3>
      <Segmented<Status> value={item.status} label={t('detail.status')} onChange={(status) => up({ status })} options={STATUSES.map((s) => ({ value: s, label: t(`status.${item.kind}.${s}`) }))} />

      <div className="toggles">
        <label className="toggle">
          <input type="checkbox" checked={!item.owned} onChange={(e) => up({ owned: !e.target.checked })} />
          {t('detail.wishlist')}
        </label>
        <label className="toggle">
          <input type="checkbox" checked={item.recommend} onChange={(e) => up({ recommend: e.target.checked })} />
          👍 {t('detail.recommend')}
        </label>
        {item.kind === 'book' && (
          <label className="toggle">
            {t('field.format')}
            <select value={item.format} onChange={(e) => up({ format: e.target.value as Item['format'] })}>
              <option value="physical">{t('format.physical')}</option>
              <option value="ebook">{t('format.ebook')}</option>
              <option value="audio">{t('format.audio')}</option>
            </select>
          </label>
        )}
      </div>

      {item.owned && item.format === 'physical' && (
        <>
          <h3>{t('detail.place')}</h3>
          <div className="row gap">
            <Suggest id="d-rooms" value={item.room ?? ''} options={rooms} placeholder={t('field.room')} label={t('field.room')} onChange={(room) => up({ room })} />
            <Suggest id="d-shelves" value={item.shelf ?? ''} options={shelves} placeholder={t('field.shelf')} label={t('field.shelf')} onChange={(shelf) => up({ shelf })} />
          </div>

          <h3>{t('detail.loan')}</h3>
          {loan ? (
            <div className="row gap center">
              <span>{t('detail.lentTo', { name: loan.to, date: fmtDate(loan.since) })}</span>
              <button className="btn small" onClick={giveBack}>
                ↩ {t('detail.returned')}
              </button>
            </div>
          ) : lending ? (
            <div className="row gap">
              <Suggest id="d-people" value={lendTo} options={knownPeople(items)} placeholder={t('detail.lendWho')} label={t('detail.lendWho')} onChange={setLendTo} />
              <button className="btn primary" onClick={lend} disabled={!lendTo.trim()}>
                {t('ok')}
              </button>
            </div>
          ) : (
            <button className="btn small" onClick={() => setLending(true)}>
              ↗ {t('detail.lend')}
            </button>
          )}
          {item.loans.filter((l) => l.returned).length > 0 && (
            <ul className="loan-history muted small">
              {item.loans
                .filter((l) => l.returned)
                .map((l, i) => (
                  <li key={i}>{t('detail.loanPast', { name: l.to, from: fmtDate(l.since), to: fmtDate(l.returned!) })}</li>
                ))}
            </ul>
          )}
        </>
      )}

      <h3>{t('field.notes')}</h3>
      <TextField multiline value={item.notes ?? ''} placeholder={t('detail.notesPh')} aria-label={t('field.notes')} onCommit={(notes) => up({ notes })} />

      <dl className="facts">
        {facts
          .filter(([, v]) => v !== undefined && v !== '')
          .map(([k, v]) => (
            <div key={k}>
              <dt>{k}</dt>
              <dd>{v}</dd>
            </div>
          ))}
      </dl>
      {item.description && (
        <>
          <p className={moreInfo ? 'desc' : 'desc clamp'}>{item.description}</p>
          <button className="link" onClick={() => setMoreInfo(!moreInfo)}>
            {moreInfo ? t('less') : t('more')}
          </button>
        </>
      )}
      {!item.needsCheck && (!item.coverUrl && !item.coverData ? true : !item.publisher) && (
        <button className="btn small ghost" onClick={enrich}>
          🔎 {t('detail.enrich')}
        </button>
      )}
    </Sheet>
  )
}
