import { useMemo } from 'react'
import { useLang } from '../i18n'
import { allCategories } from '../logic/categories'
import { allRooms } from '../logic/items'
import { useStore } from '../store'
import { DEFAULT_ROOMS } from '../types'

export function useRooms(): string[] {
  const { items, settings } = useStore()
  const { pick } = useLang()
  return useMemo(() => allRooms(items, settings.rooms, DEFAULT_ROOMS.map(pick)), [items, settings.rooms, pick])
}

/** Category list in display order (configured or default, plus any in use). */
export function useCategories(): string[] {
  const { items, settings } = useStore()
  return useMemo(() => allCategories(settings.categories, items.map((i) => i.category)), [items, settings.categories])
}
