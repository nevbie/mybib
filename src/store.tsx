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
  /** Replace each kept entry by its merged version and delete the rest (duplicate merging). */
  applyMerges(merges: { keep: Item; remove: string[] }[]): void
  importItems(items: Item[], updateOnly?: boolean, removedThere?: string[]): Promise<{ added: number; updated: number; skipped: number; removed: number }>
  /** ids deleted or merged away on this device – kept so imports don't bring them back */
  removedIds: string[]
  /** Rename a category on all items ('' removes it). */
  moveCategory(from: string, to: string): void
  replaceAll(items: Item[]): Promise<void>
  /** Bulk edit: apply the same change (or a per-item change) to many items. */
  updateItems(ids: string[], patch: Partial<Item> | ((i: Item) => Partial<Item>)): void
  /** Move everything in one room to another – also used to rename rooms. */
  moveRoom(from: string, to: string): void
  updateSettings(patch: Partial<Settings>): void
}

const Ctx = createContext<StoreValue | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Item[]>([])
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS)
  const [ready, setReady] = useState(false)
  const [removedIds, setRemovedIds] = useState<string[]>([])
  const itemsRef = useRef(items)
  const removedRef = useRef<string[]>([])
  itemsRef.current = items

  useEffect(() => {
    Promise.all([db.loadItems(), db.getKV<Partial<Settings>>('settings'), db.getKV<string[]>('removed')])
      .then(([stored, s, removed]) => {
        removedRef.current = removed ?? []
        setRemovedIds(removedRef.current)
        // bring older data up to date (e.g. shelves → rooms) and save it once
        const list = stored.map((i) => normalizeItem(i))
        const changed = list.filter((i, n) => JSON.stringify(i) !== JSON.stringify(stored[n]))
        if (changed.length) db.putItems(changed).catch(() => {})
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

  /** Remember deleted ids (tombstones), so a later import of an older backup doesn't bring them back. */
  const remember = useCallback((ids: string[]) => {
    if (!ids.length) return
    removedRef.current = [...new Set([...removedRef.current, ...ids])]
    setRemovedIds(removedRef.current)
    db.setKV('removed', removedRef.current).catch(() => {})
  }, [])

  const removeItems = useCallback((ids: string[]) => {
    remember(ids)
    const set = new Set(ids)
    setItems((s) => s.filter((i) => !set.has(i.id)))
    db.deleteItems(ids).catch((e) => alert(String(e)))
  }, [remember])

  const applyMerges = useCallback(
    (merges: { keep: Item; remove: string[] }[]) => {
      const now = new Date().toISOString()
      const kept = new Map(merges.map((m) => [m.keep.id, normalizeItem({ ...m.keep, updatedAt: now })]))
      const gone = new Set(merges.flatMap((m) => m.remove))
      remember([...gone])
      setItems(itemsRef.current.filter((i) => !gone.has(i.id)).map((i) => kept.get(i.id) ?? i))
      persist([...kept.values()])
      db.deleteItems([...gone]).catch((e) => alert(String(e)))
    },
    [persist, remember],
  )

  const importItems = useCallback(async (incoming: Item[], updateOnly = false, removedThere: string[] = []) => {
    const r = mergeItems(itemsRef.current, incoming, updateOnly, removedRef.current, removedThere)
    const keep = new Set(r.items.map((i) => i.id))
    const dropped = itemsRef.current.filter((i) => !keep.has(i.id)).map((i) => i.id)
    setItems(r.items)
    await db.putItems(r.items)
    if (dropped.length) {
      await db.deleteItems(dropped)
      remember(dropped)
    }
    return { added: r.added, updated: r.updated, skipped: r.skipped, removed: r.removed }
  }, [remember])

  /** Start over (wipe) or restore: also forgets deleted ids, so a backup can bring everything back. */
  const replaceAll = useCallback(async (list: Item[]) => {
    removedRef.current = []
    setRemovedIds([])
    await db.setKV('removed', [])
    await db.clearItems()
    await db.putItems(list)
    setItems(list)
  }, [])

  const updateItems = useCallback(
    (ids: string[], patch: Partial<Item> | ((i: Item) => Partial<Item>)) => {
      const set = new Set(ids)
      const now = new Date().toISOString()
      const changed: Item[] = []
      const next = itemsRef.current.map((i) => {
        if (!set.has(i.id)) return i
        const n = normalizeItem({ ...i, ...(typeof patch === 'function' ? patch(i) : patch), id: i.id, updatedAt: now })
        changed.push(n)
        return n
      })
      setItems(next)
      persist(changed)
    },
    [persist],
  )

  const moveRoom = useCallback(
    (from: string, to: string) => {
      const ids = itemsRef.current.filter((i) => (i.room ?? '') === from).map((i) => i.id)
      updateItems(ids, { room: to || undefined })
    },
    [updateItems],
  )

  const moveCategory = useCallback(
    (from: string, to: string) => {
      const ids = itemsRef.current.filter((i) => i.category === from).map((i) => i.id)
      updateItems(ids, { category: to || undefined })
    },
    [updateItems],
  )

  const updateSettings = useCallback((patch: Partial<Settings>) => {
    setSettings((s) => {
      const n = { ...s, ...patch }
      db.setKV('settings', n).catch(() => {})
      return n
    })
  }, [])

  const byId = useMemo(() => new Map(items.map((i) => [i.id, i])), [items])

  const value: StoreValue = { ready, items, byId, settings, addItems, updateItem, removeItems, applyMerges, importItems, removedIds, replaceAll, updateItems, moveRoom, moveCategory, updateSettings }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): StoreValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useStore outside StoreProvider')
  return v
}
