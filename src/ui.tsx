import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import type { Candidate } from './logic/lookup'
import { EMPTY_FILTERS, type Filters, type SortKey } from './logic/items'
import type { ItemDraft, Kind } from './types'

export type TabId = 'library' | 'add' | 'places' | 'settings'
export type ViewMode = 'list' | 'compact' | 'grid' | 'shelf'

/** What the library looked like last time (filters, sort, view) – kept on this device. */
const SAVED = 'mybib.ui'
function loadSaved(): { filters?: Partial<Filters>; sort?: SortKey; view?: ViewMode } {
  try {
    return JSON.parse(localStorage.getItem(SAVED) ?? '{}')
  } catch {
    return {}
  }
}

/** Overlays (sheets) stacked on top of the current tab. The phone's back button closes the top one. */
export type Overlay =
  | { type: 'item'; id: string }
  | { type: 'form'; id?: string; draft?: ItemDraft }
  | { type: 'scan' }
  | { type: 'bulk' }
  | { type: 'tidy' }
  | { type: 'covers'; ids?: string[] }
  | { type: 'rotate'; ids?: string[] }
  | { type: 'merge'; ids: string[] }
  | { type: 'bulkEdit'; ids: string[] }
  | { type: 'photo'; mode: 'shelf' | 'cover' }
  | { type: 'search'; kind: Kind; title: string; creator: string; resolve(c: Candidate | null): void }

interface UIValue {
  tab: TabId
  go(tab: TabId): void
  filters: Filters
  setFilters(f: Filters): void
  sort: SortKey
  setSort(s: SortKey): void
  view: ViewMode
  setView(v: ViewMode): void
  overlays: Overlay[]
  open(o: Overlay): void
  close(): void
  openItem(id: string): void
  openForm(id?: string, draft?: ItemDraft): void
  /** Online search sheet; resolves with the picked result (or null when closed). */
  pickCandidate(kind: Kind, title?: string, creator?: string): Promise<Candidate | null>
  /** Close the search sheet and hand back the result. */
  finishSearch(c: Candidate | null): void
}

const Ctx = createContext<UIValue | null>(null)
const TABS: TabId[] = ['library', 'add', 'places', 'settings']

function tabFromHash(): TabId {
  const h = location.hash.replace('#/', '') as TabId
  return TABS.includes(h) ? h : 'library'
}

export function UIProvider({ children }: { children: ReactNode }) {
  const [overlays, setOverlays] = useState<Overlay[]>([])
  const [tab, setTab] = useState<TabId>(tabFromHash)
  const [saved] = useState(loadSaved)
  const [filters, setFilters] = useState<Filters>({ ...EMPTY_FILTERS, ...saved.filters })
  const [sort, setSort] = useState<SortKey>(saved.sort ?? 'title')
  const [view, setView] = useState<ViewMode>(saved.view ?? 'list')
  useEffect(() => {
    try {
      localStorage.setItem(SAVED, JSON.stringify({ filters, sort, view }))
    } catch {
      /* private mode – just not remembered */
    }
  }, [filters, sort, view])
  const depth = useRef(0)
  const pending = useRef<Candidate | null>(null)

  useEffect(() => {
    const onPop = () => {
      if (depth.current > 0) {
        depth.current--
        const result = pending.current
        pending.current = null
        setOverlays((o) => {
          const top = o[o.length - 1]
          // resolve after the overlay is gone, so callers can safely open the next one
          if (top?.type === 'search') setTimeout(() => top.resolve(result), 0)
          return o.slice(0, -1)
        })
      } else setTab(tabFromHash())
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  const open = useCallback((o: Overlay) => {
    depth.current++
    history.pushState({ overlay: depth.current }, '')
    setOverlays((s) => [...s, o])
  }, [])

  const close = useCallback(() => {
    if (depth.current > 0) history.back()
  }, [])

  const go = useCallback((id: TabId) => {
    // leave any open sheets behind when switching tabs
    if (depth.current > 0) {
      history.go(-depth.current)
      depth.current = 0
      setOverlays([])
    }
    history.replaceState(null, '', `#/${id}`)
    setTab(id)
    window.scrollTo(0, 0)
  }, [])

  const value: UIValue = {
    tab,
    go,
    filters,
    setFilters,
    sort,
    setSort,
    view,
    setView,
    overlays,
    open,
    close,
    openItem: (id) => open({ type: 'item', id }),
    openForm: (id, draft) => open({ type: 'form', id, draft }),
    pickCandidate: (kind, title = '', creator = '') =>
      new Promise((resolve) => {
        let done = false
        open({
          type: 'search',
          kind,
          title,
          creator,
          resolve: (c) => {
            if (done) return
            done = true
            resolve(c)
          },
        })
      }),
    finishSearch: (c) => {
      pending.current = c
      close()
    },
  }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useUI(): UIValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useUI outside UIProvider')
  return v
}
