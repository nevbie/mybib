import { useMemo, useState } from 'react'
import { Cover } from '../components/bits'
import { Sheet } from '../components/Sheet'
import { useLang } from '../i18n'
import { categoryLabel } from '../logic/categories'
import { differingFields, mergeGroup, mergeValue, mergeWithChoices, type MergeField } from '../logic/items'
import { useStore } from '../store'
import type { Item } from '../types'
import { useUI } from '../ui'

const LABEL: Record<MergeField, string> = {
  cover: 'merge.cover',
  title: 'field.title',
  subtitle: 'field.subtitle',
  creators: 'merge.creators',
  series: 'field.seriesOnly',
  volume: 'field.volume',
  publisher: 'field.publisher',
  year: 'field.year',
  isbn: 'field.isbn',
  language: 'field.language',
  pages: 'field.pages',
  kind: 'field.kind',
  format: 'field.format',
  category: 'field.category',
  room: 'field.room',
  description: 'merge.description',
  status: 'detail.status',
  rating: 'rating',
}

/**
 * Merge several entries into one and choose, field by field, whose value to keep (cover, author, volume …).
 * Notes, tags and loans of all entries are kept together.
 */
export function MergeSheet({ ids }: { ids: string[] }) {
  const { t, lang } = useLang()
  const ui = useUI()
  const { byId, applyMerges } = useStore()
  const group = useMemo(() => ids.map((id) => byId.get(id)).filter((i): i is Item => !!i), [ids, byId])
  const fields = useMemo(() => differingFields(group), [group])
  // default choice per field = what the automatic merge would keep
  const auto = useMemo(() => (group.length > 1 ? mergeGroup(group).keep : undefined), [group])
  const [choices, setChoices] = useState<Partial<Record<MergeField, string>>>({})
  if (group.length < 2 || !auto) return null

  const chosen = (f: MergeField) => choices[f] ?? group.find((i) => mergeValue(i, f) === mergeValue(auto, f))?.id ?? group[0].id

  const show = (i: Item, f: MergeField) => {
    const v = mergeValue(i, f)
    if (!v) return <span className="muted">{t('merge.empty')}</span>
    if (f === 'cover') return <Cover item={i} />
    if (f === 'kind') return t(`kind.${v}`)
    if (f === 'format') return t(`format.${v}`)
    if (f === 'status') return t(`status.${i.kind}.${v}`)
    if (f === 'category') return categoryLabel(v, lang)
    if (f === 'rating') return '★'.repeat(i.rating)
    if (f === 'description') return v.length > 140 ? v.slice(0, 140) + ' …' : v
    return v
  }

  const merge = () => {
    const all = Object.fromEntries(fields.map((f) => [f, chosen(f)])) as Partial<Record<MergeField, string>>
    const m = mergeWithChoices(group, all)
    applyMerges([m])
    ui.close()
    setTimeout(() => ui.openItem(m.keep.id), 50)
  }

  return (
    <Sheet
      title={`🔗 ${t('merge.title', { n: group.length })}`}
      onClose={ui.close}
      footer={
        <button className="btn primary wide" onClick={merge}>
          🔗 {t('merge.apply', { n: group.length })}
        </button>
      }
    >
      <p className="muted small">{t('merge.intro')}</p>
      {fields.length === 0 && <p className="muted">{t('merge.same')}</p>}
      {fields.map((f) => (
        <fieldset key={f} className="merge-field">
          <legend>{t(LABEL[f])}</legend>
          <div className={f === 'cover' ? 'merge-options covers' : 'merge-options'}>
            {group.map((i) => (
              <label key={i.id} className={chosen(f) === i.id ? 'merge-option on' : 'merge-option'}>
                <input type="radio" name={`m-${f}`} checked={chosen(f) === i.id} onChange={() => setChoices((c) => ({ ...c, [f]: i.id }))} />
                <span>{show(i, f)}</span>
              </label>
            ))}
          </div>
        </fieldset>
      ))}
      <p className="muted small">{t('merge.combined')}</p>
    </Sheet>
  )
}
