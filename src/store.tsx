import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import * as db from './db'
import { mergeItems, normalizeItem } from './logic/items'
import { DEFAULT_SETTINGS, type Item, type ItemDraft, type Settings } from './types'

interface StoreValue {
  ready: boolean
  items: Item[]
  byId: Map<string, Item>
  settings: Settings
  addItems(drafts: ItemDraft[]): Promise<Item[]>
  updateItem(id: string, patch: Partial<Item>): void
  removeItems(ids: string[]): void
  importItems(items: Item[]): Promise<{ added: number; updated: number; skipped: number }>
  replaceAll(items: Item[]): Promise<void>
  /** Move everything in room (and optionally shelf) to a new room/shelf – also used to rename. */
  movePlace(from: { room: string; shelf?: string }, to: { room: string; shelf?: string }): void
  updateSettings(patch: Partial<Settings>): void
}

const Ctx = createContext<StoreValue | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Item[]>([])
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS)
  const [ready, setReady] = useState(false)
  const itemsRef = useRef(items)
  itemsRef.current = items

  useEffect(() => {
    Promise.all([db.loadItems(), db.getKV<Partial<Settings>>('settings')])
      .then(([list, s]) => {
        setItems(list)
        setSettings({ ...DEFAULT_SETTINGS, ...s })
      })
      .catch((e) => console.error('loading failed', e))
      .finally(() => setReady(true))
  }, [])

  const persist = useCallback((changed: Item[]) => {
    db.putItems(changed).catch((e) => alert('Speichern fehlgeschlagen / Saving failed: ' + e))
  }, [])

  const addItems = useCallback(
    async (drafts: ItemDraft[]) => {
      const now = new Date().toISOString()
      const created = drafts.map((d) => normalizeItem({ ...d, id: undefined, addedAt: now, updatedAt: now }, now))
      setItems((s) => [...s, ...created])
      await db.putItems(created)
      return created
    },
    [],
  )

  const updateItem = useCallback(
    (id: string, patch: Partial<Item>) => {
      const old = itemsRef.current.find((i) => i.id === id)
      if (!old) return
      const next = normalizeItem({ ...old, ...patch, id, updatedAt: new Date().toISOString() })
      setItems((s) => s.map((i) => (i.id === id ? next : i)))
      persist([next])
    },
    [persist],
  )

  const removeItems = useCallback((ids: string[]) => {
    const set = new Set(ids)
    setItems((s) => s.filter((i) => !set.has(i.id)))
    db.deleteItems(ids).catch((e) => alert(String(e)))
  }, [])

  const importItems = useCallback(async (incoming: Item[]) => {
    const r = mergeItems(itemsRef.current, incoming)
    setItems(r.items)
    await db.putItems(r.items)
    return { added: r.added, updated: r.updated, skipped: r.skipped }
  }, [])

  const replaceAll = useCallback(async (list: Item[]) => {
    await db.clearItems()
    await db.putItems(list)
    setItems(list)
  }, [])

  const movePlace = useCallback(
    (from: { room: string; shelf?: string }, to: { room: string; shelf?: string }) => {
      const now = new Date().toISOString()
      const changed: Item[] = []
      const next = itemsRef.current.map((i) => {
        if ((i.room ?? '') !== from.room) return i
        if (from.shelf !== undefined && (i.shelf ?? '') !== from.shelf) return i
        const n = normalizeItem({ ...i, room: to.room || undefined, shelf: to.shelf !== undefined ? to.shelf || undefined : i.shelf, updatedAt: now })
        changed.push(n)
        return n
      })
      setItems(next)
      persist(changed)
    },
    [persist],
  )

  const updateSettings = useCallback((patch: Partial<Settings>) => {
    setSettings((s) => {
      const n = { ...s, ...patch }
      db.setKV('settings', n).catch(() => {})
      return n
    })
  }, [])

  const byId = useMemo(() => new Map(items.map((i) => [i.id, i])), [items])

  const value: StoreValue = { ready, items, byId, settings, addItems, updateItem, removeItems, importItems, replaceAll, movePlace, updateSettings }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): StoreValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useStore outside StoreProvider')
  return v
}
