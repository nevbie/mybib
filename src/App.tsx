import { useLang } from './i18n'
import { useStore } from './store'
import { useUI, type TabId } from './ui'
import { AddView } from './views/AddView'
import { BulkSheet } from './views/BulkSheet'
import { ItemDetail } from './views/ItemDetail'
import { ItemForm } from './views/ItemForm'
import { LibraryView } from './views/LibraryView'
import { PhotoSheet } from './views/PhotoSheet'
import { PlacesView } from './views/PlacesView'
import { ScanSheet } from './views/ScanSheet'
import { SearchSheet } from './views/SearchSheet'
import { SettingsView } from './views/SettingsView'

const TABS: { id: TabId; icon: string; label: string }[] = [
  { id: 'library', icon: '📚', label: 'nav.library' },
  { id: 'add', icon: '＋', label: 'nav.add' },
  { id: 'places', icon: '🏠', label: 'nav.places' },
  { id: 'settings', icon: '⚙︎', label: 'nav.settingsShort' },
]

export function App() {
  const { t } = useLang()
  const ui = useUI()
  const { items } = useStore()
  const toCheck = items.filter((i) => i.needsCheck).length

  return (
    <div className="app">
      <main>
        {ui.tab === 'library' && <LibraryView />}
        {ui.tab === 'add' && <AddView />}
        {ui.tab === 'places' && <PlacesView />}
        {ui.tab === 'settings' && <SettingsView />}
      </main>
      <nav className="tabbar">
        {TABS.map((x) => (
          <button key={x.id} className={ui.tab === x.id ? 'on' : ''} onClick={() => ui.go(x.id)} aria-current={ui.tab === x.id ? 'page' : undefined}>
            <span className="tab-icon" aria-hidden>
              {x.icon}
              {x.id === 'library' && toCheck > 0 && <span className="tab-dot" />}
            </span>
            <span className="tab-label">{t(x.label)}</span>
          </button>
        ))}
      </nav>
      {ui.overlays.map((o, i) => {
        switch (o.type) {
          case 'item':
            return <ItemDetail key={i} id={o.id} />
          case 'form':
            return <ItemForm key={i} id={o.id} draft={o.draft} />
          case 'bulk':
            return <BulkSheet key={i} />
          case 'scan':
            return <ScanSheet key={i} />
          case 'photo':
            return <PhotoSheet key={i} mode={o.mode} />
          case 'search':
            return <SearchSheet key={i} kind={o.kind} title={o.title} creator={o.creator} />
        }
      })}
    </div>
  )
}
