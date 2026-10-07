import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { dictionaries } from '../i18n'
import { FORMATS, KINDS, STATUSES } from '../types'

function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f)
    if (statSync(p).isDirectory()) return f === '__tests__' ? [] : sources(p)
    return /\.tsx?$/.test(f) ? [p] : []
  })
}

describe('translations', () => {
  const de = dictionaries.de as Record<string, string>
  const en = dictionaries.en as Record<string, string>

  it('has the same keys and placeholders in both languages', () => {
    expect(Object.keys(en).sort()).toEqual(Object.keys(de).sort())
    for (const k of Object.keys(de)) {
      const ph = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort()
      expect(ph(en[k]), k).toEqual(ph(de[k]))
    }
  })

  it('defines every literal key used in the code', () => {
    const src = sources(join(__dirname, '..')).map((f) => readFileSync(f, 'utf8')).join('\n')
    const keys = new Set<string>()
    for (const m of src.matchAll(/\bt\(\s*'([^']+)'/g)) keys.add(m[1])
    for (const m of src.matchAll(/\bt\([^)]*?\?\s*'([^']+)'\s*:\s*'([^']+)'/g)) (keys.add(m[1]), keys.add(m[2]))
    for (const m of src.matchAll(/label: '([a-z]+\.[A-Za-z.]+)'/g)) keys.add(m[1])
    const missing = [...keys].filter((k) => !(k in de))
    expect(missing).toEqual([])
  })

  it('defines all generated keys', () => {
    const gen = [
      ...KINDS.flatMap((k) => [`kind.${k}`, `kind.${k}.pl`, `creator.${k}`, ...STATUSES.map((s) => `status.${k}.${s}`)]),
      ...FORMATS.map((f) => `format.${f}`),
      ...['all', 'owned', 'wish', 'lent', 'recommend', 'check'].map((s) => `scope.${s}`),
      ...['title', 'creator', 'added', 'rating', 'year', 'place'].map((s) => `sort.${s}`),
      ...['cover', 'publisher', 'year', 'isbn', 'description'].map((s) => `bulk.field.${s}`),
      ...['auth', 'refusal', 'rate', 'network', 'parse', 'other'].map((s) => `ai.err.${s}`),
      'ai.conf.medium',
      'ai.conf.low',
      'settings.model.claude-opus-5-5',
      'settings.model.claude-sonnet-5-5',
    ]
    expect(gen.filter((k) => !(k in de))).toEqual([])
  })
})
