import { afterEach, describe, expect, it, vi } from 'vitest'
import { bulkTargets, missingInfo } from '../logic/bulk'
import { normalizeItem } from '../logic/items'
import { enrichPatch, findBestMatch, takeGoogleProblem } from '../logic/lookup'

const item = (p: Record<string, unknown>) => normalizeItem({ title: 'x', ...p } as never)

// Image is a browser API – pretend every cover loads
class FakeImage {
  naturalWidth = 300
  onload: (() => void) | null = null
  onerror: (() => void) | null = null
  set src(_: string) {
    setTimeout(() => this.onload?.(), 0)
  }
}

function mockFetch(handler: (url: string) => { status?: number; body?: unknown }) {
  vi.stubGlobal('Image', FakeImage)
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const r = handler(url)
      const status = r.status ?? 200
      return { ok: status < 300, status, json: async () => r.body ?? {} }
    }),
  )
}

const gVolume = (title: string, authors: string[], extra: Record<string, unknown> = {}) => ({
  volumeInfo: { title, authors, publisher: 'Suhrkamp', publishedDate: '2012-03-01', industryIdentifiers: [{ type: 'ISBN_13', identifier: '9783518464' }], imageLinks: { thumbnail: 'http://books.google.com/x&edge=curl' }, ...extra },
})

afterEach(() => vi.unstubAllGlobals())

describe('bulk targets', () => {
  it('lists books with missing details not tried yet', () => {
    const full = item({ title: 'A', coverUrl: 'u', publisher: 'p', year: 2000, isbn: '9780000000000', description: 'd' })
    const bare = item({ title: 'B' })
    const tried = item({ title: 'C', lookedUp: '2026-10-01' })
    const game = item({ title: 'D', kind: 'game' })
    expect(missingInfo(full)).toEqual([])
    expect(missingInfo(bare)).toEqual(['cover', 'publisher', 'year', 'isbn', 'description'])
    expect(bulkTargets([full, bare, tried, game], false).map((i) => i.title)).toEqual(['B'])
    expect(bulkTargets([full, bare, tried, game], true).map((i) => i.title)).toEqual(['B', 'C'])
  })
  it('keeps lookedUp through normalisation', () => {
    expect(item({ lookedUp: '2026-10-01' }).lookedUp).toBe('2026-10-01')
  })
})

describe('enrichPatch', () => {
  it('fills only empty fields and never overwrites', () => {
    const i = item({ title: 'Open City', creators: ['Teju Cole'], publisher: 'Mein Verlag' })
    const p = enrichPatch(i, { via: 'g', title: 'Open City', creators: ['Cole, Teju'], publisher: 'Suhrkamp', year: 2012, coverUrl: 'c', description: '' })
    expect(p).toEqual({ year: 2012, coverUrl: 'c' })
  })
})

describe('findBestMatch', () => {
  it('takes a clear title + author match from Google Books', async () => {
    mockFetch((url) => (url.includes('googleapis') ? { body: { items: [gVolume('Something else', ['X']), gVolume('Open City', ['Teju Cole'])] } } : { body: { docs: [] } }))
    const c = await findBestMatch(item({ title: 'Open City', creators: ['Teju Cole'] }))
    expect(c).toMatchObject({ title: 'Open City', publisher: 'Suhrkamp', year: 2012, coverUrl: 'https://books.google.com/x' })
  })
  it('rejects a match by a different author', async () => {
    mockFetch((url) => (url.includes('googleapis') ? { body: { items: [gVolume('Open City', ['Someone Else'])] } } : { body: { docs: [] } }))
    expect(await findBestMatch(item({ title: 'Open City', creators: ['Teju Cole'] }))).toBeNull()
  })
  it('needs an exact title when the author is unknown', async () => {
    mockFetch((url) => (url.includes('googleapis') ? { body: { items: [gVolume('Sahara Reiseführer Marokko', ['A'])] } } : { body: { docs: [] } }))
    expect(await findBestMatch(item({ title: 'Sahara Marokko' }))).toBeNull()
    mockFetch((url) => (url.includes('googleapis') ? { body: { items: [gVolume('Die großen Weisheiten der Bibel', ['A'])] } } : { body: { docs: [] } }))
    expect((await findBestMatch(item({ title: 'Die grossen Weisheiten der Bibel' })))?.publisher).toBe('Suhrkamp')
  })
  it('reports the Google quota', async () => {
    mockFetch((url) => (url.includes('googleapis') ? { status: 429 } : { body: { docs: [] } }))
    takeGoogleProblem()
    expect(await findBestMatch(item({ title: 'Open City', creators: ['Teju Cole'] }))).toBeNull()
    expect(takeGoogleProblem()).toBe('quota')
    expect(takeGoogleProblem()).toBe('')
  })
  it('uses the ISBN when there is one', async () => {
    mockFetch((url) => {
      if (url.includes('googleapis')) return { body: { items: [gVolume('Open City', ['Teju Cole'])] } }
      return { body: {} }
    })
    const c = await findBestMatch(item({ title: 'whatever', creators: [], isbn: '9783518464547' }))
    expect(c?.title).toBe('Open City')
    expect(vi.mocked(fetch).mock.calls[0][0]).toContain('isbn%3A9783518464547')
  })
})
