import type { ItemDraft, Kind } from '../types'

/** Result types of the photo recognition – kept apart from ai.ts so the SDK is only loaded when needed. */

export interface Recognized {
  kind: Kind
  title: string
  creators: string[]
  series: string
  volume: string
  publisher: string
  language: string
  /** how sure the model is about the reading */
  confidence: 'high' | 'medium' | 'low'
  /** e.g. "spine partly hidden", "title guessed from publisher series" */
  remark: string
}

export class RecognizeError extends Error {
  constructor(
    public code: 'auth' | 'refusal' | 'rate' | 'network' | 'parse' | 'other',
    message: string,
  ) {
    super(message)
  }
}

/** Turn a recognised entry into an item draft. */
export function toDraft(r: Recognized): ItemDraft {
  return {
    kind: r.kind,
    title: r.title.trim(),
    creators: r.creators.map((c) => c.trim()).filter(Boolean),
    series: r.series || undefined,
    volume: r.volume || undefined,
    publisher: r.publisher || undefined,
    language: r.language || undefined,
    needsCheck: r.confidence !== 'high' ? true : undefined,
    source: 'ai',
  }
}
