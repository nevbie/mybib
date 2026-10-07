import { useRef } from 'react'
import { useLang } from '../i18n'
import { parseImport } from '../logic/items'
import { useStore } from '../store'
import { useUI } from '../ui'

export function AddView() {
  const { t } = useLang()
  const ui = useUI()
  const { settings, importItems } = useStore()
  const fileRef = useRef<HTMLInputElement>(null)

  const pickSearch = async () => {
    const c = await ui.pickCandidate('book')
    if (!c) return
    const { via: _via, ...draft } = c
    ui.openForm(undefined, { ...draft, source: 'search' })
  }

  const onImport = async (f?: File) => {
    if (!f) return
    try {
      const list = parseImport(await f.text())
      const r = await importItems(list)
      alert(t('data.imported', r))
    } catch (e) {
      alert(t('data.importError', { e: String((e as Error).message ?? e) }))
    }
  }

  const ways: { icon: string; title: string; text: string; onClick(): void }[] = [
    { icon: '▥', title: t('add.scan'), text: t('add.scanText'), onClick: () => ui.open({ type: 'scan' }) },
    { icon: '📸', title: t('add.shelf'), text: settings.claudeKey ? t('add.shelfText') : t('add.shelfTextNoKey'), onClick: () => ui.open({ type: 'photo', mode: 'shelf' }) },
    { icon: '🖼', title: t('add.cover'), text: t('add.coverText'), onClick: () => ui.open({ type: 'photo', mode: 'cover' }) },
    { icon: '🔎', title: t('add.search'), text: t('add.searchText'), onClick: pickSearch },
    { icon: '✍️', title: t('add.manual'), text: t('add.manualText'), onClick: () => ui.openForm() },
    { icon: '📥', title: t('add.import'), text: t('add.importText'), onClick: () => fileRef.current?.click() },
  ]

  return (
    <div className="page">
      <h1>{t('nav.add')}</h1>
      <div className="ways">
        {ways.map((w) => (
          <button key={w.title} className="way" onClick={w.onClick}>
            <span className="way-icon" aria-hidden>
              {w.icon}
            </span>
            <span>
              <strong>{w.title}</strong>
              <span className="muted small">{w.text}</span>
            </span>
          </button>
        ))}
      </div>
      <input ref={fileRef} type="file" accept="application/json,.json" hidden onChange={(e) => (onImport(e.target.files?.[0]), (e.target.value = ''))} />
      <p className="muted small">{t('add.tip')}</p>
    </div>
  )
}
