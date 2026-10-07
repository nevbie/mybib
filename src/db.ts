import type { Item } from './types'

/**
 * Tiny IndexedDB wrapper. Everything lives on this device only; backups are JSON exports.
 * IndexedDB (unlike localStorage) has room for thousands of items with cover thumbnails.
 */

const DB_NAME = 'mybib'
const VERSION = 1
const ITEMS = 'items'
const KV = 'kv'

let dbp: Promise<IDBDatabase> | null = null

function open(): Promise<IDBDatabase> {
  if (!dbp) {
    dbp = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, VERSION)
      req.onupgradeneeded = () => {
        const db = req.result
        if (!db.objectStoreNames.contains(ITEMS)) db.createObjectStore(ITEMS, { keyPath: 'id' })
        if (!db.objectStoreNames.contains(KV)) db.createObjectStore(KV)
      }
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
    // ask the browser not to evict our data when storage runs low
    navigator.storage?.persist?.().catch(() => {})
  }
  return dbp
}

function done(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}

export async function loadItems(): Promise<Item[]> {
  const db = await open()
  return new Promise((resolve, reject) => {
    const req = db.transaction(ITEMS).objectStore(ITEMS).getAll()
    req.onsuccess = () => resolve(req.result as Item[])
    req.onerror = () => reject(req.error)
  })
}

export async function putItems(items: Item[]): Promise<void> {
  const db = await open()
  const tx = db.transaction(ITEMS, 'readwrite')
  const store = tx.objectStore(ITEMS)
  for (const i of items) store.put(i)
  return done(tx)
}

export async function deleteItems(ids: string[]): Promise<void> {
  const db = await open()
  const tx = db.transaction(ITEMS, 'readwrite')
  const store = tx.objectStore(ITEMS)
  for (const id of ids) store.delete(id)
  return done(tx)
}

export async function clearItems(): Promise<void> {
  const db = await open()
  const tx = db.transaction(ITEMS, 'readwrite')
  tx.objectStore(ITEMS).clear()
  return done(tx)
}

export async function getKV<T>(key: string): Promise<T | undefined> {
  const db = await open()
  return new Promise((resolve, reject) => {
    const req = db.transaction(KV).objectStore(KV).get(key)
    req.onsuccess = () => resolve(req.result as T | undefined)
    req.onerror = () => reject(req.error)
  })
}

export async function setKV(key: string, value: unknown): Promise<void> {
  const db = await open()
  const tx = db.transaction(KV, 'readwrite')
  tx.objectStore(KV).put(value, key)
  return done(tx)
}
