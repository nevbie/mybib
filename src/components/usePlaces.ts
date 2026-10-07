import { useMemo } from 'react'
import { useLang } from '../i18n'
import { allRooms } from '../logic/items'
import { useStore } from '../store'
import { DEFAULT_ROOMS } from '../types'

export function useRooms(): string[] {
  const { items, settings } = useStore()
  const { pick } = useLang()
  return useMemo(() => allRooms(items, settings.rooms, DEFAULT_ROOMS.map(pick)), [items, settings.rooms, pick])
}
