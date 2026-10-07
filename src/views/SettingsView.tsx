import { useRef, useState } from 'react'
import { Segmented, TextField } from '../components/bits'
import { useLang } from '../i18n'
import { parseImportFile, toCSV, toExport } from '../logic/items'
import { useStore } from '../store'
import { categoryLabel, toCategory } from '../logic/categories'
import { useCategories } from '../components/usePlaces'
import { useUI } from '../ui'
import type { Lang } from '../types'

const MODELS: [string, string][] = [
  ['claude-opus-5-5', 'Claude Opus 5.5'],
  ['claude-sonnet-5-5', 'Claude Sonnet 5.5'],
]

function download(name: string, text: string, type: string) {
  const url = URL.createObjectURL(new Blob([text], { type }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 5000)
}

export function SettingsView() {
  const { t, lang, setLang } = useLang()
  const { items, settings, updateSettings, importItems, replaceAll, moveCategory } = useStore()
  const categories = useCategories()
  const catCount = new Map<string, number>()
  for (const i of items) if (i.category) catCount.set(i.category, (catCount.get(i.category) ?? 0) + 1)
  const saveCats = (list: string[]) => updateSettings({ categories: list.filter((c, i, a) => c && a.indexOf(c) === i) })
  const addCategory = () => {
    const name = prompt(t('cat.new'))?.trim()
    if (name) saveCats([...categories, toCategory(name)!])
  }
  const renameCategory = (c: string) => {
    const name = prompt(t('cat.rename', { name: categoryLabel(c, lang) }), categoryLabel(c, lang))?.trim()
    if (!name || name === categoryLabel(c, lang)) return
    const to = toCategory(name)!
    if (categories.includes(to) && !confirm(t('cat.mergeConfirm', { from: categoryLabel(c, lang), to: categoryLabel(to, lang) }))) return
    moveCategory(c, to)
    saveCats(categories.map((x) => (x === c ? to : x)))
  }
  const removeCategory = (c: string) => {
    const n = catCount.get(c) ?? 0
    if (!confirm(t('cat.removeConfirm', { name: categoryLabel(c, lang), n }))) return
    if (n) moveCategory(c, '')
    saveCats(categories.filter((x) => x !== c))
  }
  const ui = useUI()
  const fileRef = useRef<HTMLInputElement>(null)
  const [showKey, setShowKey] = useState(false)
  const stamp = new Date().toISOString().slice(0, 10)

  const onImport = async (f?: File) => {
    if (!f) return
    try {
      const { items: list, updateOnly } = parseImportFile(await f.text())
      alert(t('data.imported', await importItems(list, updateOnly)))
    } catch (e) {
      alert(t('data.importError', { e: String((e as Error).message ?? e) }))
    }
  }

  const wipe = async () => {
    if (!confirm(t('data.wipeConfirm', { n: items.length }))) return
    if (prompt(t('data.wipeType')) !== 'OK') return
    await replaceAll([])
  }

  return (
    <div className="page">
      <h1>{t('nav.settings')}</h1>

      <h2>{t('settings.lang')}</h2>
      <Segmented<Lang>
        value={lang}
        label={t('settings.lang')}
        onChange={setLang}
        options={[
          { value: 'de', label: 'Deutsch' },
          { value: 'en', label: 'English' },
        ]}
      />

      <h2>{t('settings.ai')}</h2>
      <p className="muted small">{t('settings.aiText')}</p>
      <label>
        {t('settings.claudeKey')}
        <div className="row gap">
          <TextField type={showKey ? 'text' : 'password'} value={settings.claudeKey} placeholder="sk-ant-…" autoComplete="off" onCommit={(claudeKey) => updateSettings({ claudeKey: claudeKey.trim() })} />
          <button className="btn small" onClick={() => setShowKey(!showKey)}>
            {showKey ? '🙈' : '👁'}
          </button>
        </div>
      </label>
      <label>
        {t('settings.model')}
        <select value={settings.claudeModel} onChange={(e) => updateSettings({ claudeModel: e.target.value })}>
          {MODELS.map(([id, name]) => (
            <option key={id} value={id}>
              {name} – {t(`settings.model.${id}`)}
            </option>
          ))}
        </select>
      </label>
      <p className="muted small">{t('settings.aiPrivacy')}</p>

      <h2>{t('settings.lookup')}</h2>
      <p className="muted small">{t('settings.lookupText')}</p>
      <label>
        {t('settings.googleKey')}
        <TextField value={settings.googleBooksKey} placeholder={t('optional')} autoComplete="off" onCommit={(googleBooksKey) => updateSettings({ googleBooksKey: googleBooksKey.trim() })} />
      </label>
      <details className="small">
        <summary>{t('settings.googleHow')}</summary>
        <ol className="muted">
          <li>{t('settings.googleHow1')}</li>
          <li>{t('settings.googleHow2')}</li>
          <li>{t('settings.googleHow3')}</li>
          <li>{t('settings.googleHow4')}</li>
        </ol>
      </details>
      <button className="btn" onClick={() => ui.open({ type: 'bulk' })}>
        ✨ {t('bulk.title')}
      </button>

      <h2>{t('settings.categories')}</h2>
      <p className="muted small">{t('settings.categoriesText')}</p>
      <ul className="cat-list">
        {categories.map((c) => (
          <li key={c}>
            <span>
              {categoryLabel(c, lang)} <span className="muted small">({catCount.get(c) ?? 0})</span>
            </span>
            <span className="row">
              <button className="icon-btn small" onClick={() => renameCategory(c)} aria-label={t('places.rename')}>
                ✎
              </button>
              <button className="icon-btn small" onClick={() => removeCategory(c)} aria-label={t('places.remove')}>
                ✕
              </button>
            </span>
          </li>
        ))}
      </ul>
      <div className="row gap wrap">
        <button className="btn small" onClick={addCategory}>
          ＋ {t('cat.add')}
        </button>
        {settings.categories.length > 0 && (
          <button className="btn small ghost" onClick={() => confirm(t('cat.resetConfirm')) && updateSettings({ categories: [] })}>
            {t('cat.reset')}
          </button>
        )}
      </div>

      <h2>{t('settings.data')}</h2>
      <p className="muted small">{t('settings.dataText', { n: items.length })}</p>
      <div className="col gap">
        <button className="btn" onClick={() => download(`mybib-${stamp}.json`, JSON.stringify(toExport(items)), 'application/json')}>
          💾 {t('data.exportJson')}
        </button>
        <button className="btn" onClick={() => download(`mybib-${stamp}.csv`, toCSV(items), 'text/csv;charset=utf-8')}>
          📊 {t('data.exportCsv')}
        </button>
        <button className="btn" onClick={() => fileRef.current?.click()}>
          📥 {t('data.import')}
        </button>
        <button className="btn danger ghost" onClick={wipe} disabled={!items.length}>
          🗑 {t('data.wipe')}
        </button>
      </div>
      <input ref={fileRef} type="file" accept="application/json,.json" hidden onChange={(e) => (onImport(e.target.files?.[0]), (e.target.value = ''))} />

      <p className="muted small about">mybib · {t('settings.about')}</p>
    </div>
  )
}
