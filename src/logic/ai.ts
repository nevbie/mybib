import Anthropic from '@anthropic-ai/sdk'
import { KINDS } from '../types'
import { RecognizeError, type Recognized } from './recognized'

/**
 * Recognise items on a shelf photo (or a single cover) with Claude's vision.
 * The API key is the user's own, stored only on this device and sent only to api.anthropic.com.
 */

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['items'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['kind', 'title', 'creators', 'series', 'volume', 'publisher', 'language', 'confidence', 'remark', 'box', 'rotation'],
        properties: {
          kind: { type: 'string', enum: [...KINDS] },
          title: { type: 'string' },
          creators: { type: 'array', items: { type: 'string' } },
          series: { type: 'string' },
          volume: { type: 'string' },
          publisher: { type: 'string' },
          language: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          remark: { type: 'string' },
          box: {
            type: 'object',
            additionalProperties: false,
            required: ['x0', 'y0', 'x1', 'y1'],
            properties: { x0: { type: 'number' }, y0: { type: 'number' }, x1: { type: 'number' }, y1: { type: 'number' } },
          },
          rotation: { type: 'integer', enum: [0, 90, 180, 270] },
        },
      },
    },
  },
} as const

const PROMPT = `This photo shows part of a private home library: book spines (often vertical, sometimes upside down or lying flat), maybe also front covers, board game boxes, DVDs or CDs.

List every item whose spine or cover you can see, from left to right and top to bottom. For each item:
- kind: "book" (including comics, picture books, magazines-with-ISBN), "game" (board/card games), "dvd" (DVD/Blu-ray) or "cd" (music CDs, audio-book CDs count as "cd").
- title: exactly as printed, in the original script (keep Chinese characters as characters, German umlauts, etc.). Use the book's real title, not the series name, when both are visible.
- creators: authors / artists / directors / designers as printed (empty array if none visible). If you are confident who the author is from the title alone (a well-known book), you may add them and say so in remark.
- series and volume: e.g. "Asterix" / "36", "bpb Schriftenreihe" / "11128", Chinese multi-volume sets "金瓶梅词话" / "1".
- publisher: if visible on the spine (Reclam, dtv, Carlsen, Ravensburger, btb, Hanser …), else "".
- language: ISO 639-1 code of the item's language ("de", "en", "zh", "tr", "la", "fr" …), "" if unclear.
- confidence: "high" if clearly readable, "medium" if partly guessed, "low" if mostly guessed.
- remark: short note on what was unclear, else "".
- box: where the item's front cover (or, for a spine, the spine) is in the photo: left x0, top y0, right x1, bottom y1, in thousandths of the image width and height (0–1000, origin top left).
- rotation: how many degrees that box must be turned clockwise so the cover's title reads upright: 0, 90, 180 or 270.

Skip things that are not catalogue items (folders, loose papers, boxes of toys, stacks of newspapers, notebooks without a title). Do not invent items you cannot see. If a spine is too blurry to read at all, skip it rather than guessing wildly.`

export interface RecognizeOptions {
  apiKey: string
  model: string
  /** JPEG/PNG as base64 without the data: prefix */
  imageBase64: string
  mediaType: 'image/jpeg' | 'image/png' | 'image/webp'
  /** optional hint from the user, e.g. "mostly Chinese classics" */
  hint?: string
  signal?: AbortSignal
}

type Content = Anthropic.Beta.BetaContentBlockParam

/** One structured-output request; returns the parsed JSON. */
async function ask<T>(o: { apiKey: string; model: string; signal?: AbortSignal }, content: Content[], schema: { [key: string]: unknown }, tooMany: string): Promise<T> {
  const client = new Anthropic({ apiKey: o.apiKey, dangerouslyAllowBrowser: true, maxRetries: 2 })
  let msg: Anthropic.Beta.BetaMessage
  try {
    msg = await client.beta.messages
      .stream(
        {
          model: o.model,
          max_tokens: 32000,
          betas: ['server-side-fallback-2026-07-01'],
          fallbacks: 'default',
          output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
          messages: [{ role: 'user', content }],
        },
        { signal: o.signal },
      )
      .finalMessage()
  } catch (e) {
    if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) throw new RecognizeError('auth', e.message)
    if (e instanceof Anthropic.RateLimitError) throw new RecognizeError('rate', e.message)
    if (e instanceof Anthropic.APIConnectionError) throw new RecognizeError('network', e.message)
    if (e instanceof Anthropic.APIError) throw new RecognizeError('other', e.message)
    throw e
  }
  if (msg.stop_reason === 'refusal') throw new RecognizeError('refusal', msg.stop_details?.explanation ?? 'refused')
  const text = msg.content.map((b) => (b.type === 'text' ? b.text : '')).join('')
  try {
    return JSON.parse(text) as T
  } catch {
    throw new RecognizeError('parse', msg.stop_reason === 'max_tokens' ? tooMany : 'unexpected answer')
  }
}

export async function recognizePhoto(o: RecognizeOptions): Promise<Recognized[]> {
  const parsed = await ask<{ items: Recognized[] }>(
    o,
    [
      { type: 'image', source: { type: 'base64', media_type: o.mediaType, data: o.imageBase64 } },
      { type: 'text', text: PROMPT + (o.hint?.trim() ? `\n\nHint from the owner: ${o.hint.trim()}` : '') },
    ],
    SCHEMA,
    'too many items in one photo – try a closer photo',
  )
  return parsed.items.filter((i) => i.title?.trim())
}

const ROTATION_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['covers'],
  properties: {
    covers: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['index', 'rotation'],
        properties: { index: { type: 'integer' }, rotation: { type: 'integer', enum: [0, 90, 180, 270] } },
      },
    },
  },
} as const

/**
 * For each cover photo (JPEG data URLs, best ≤ 20 per call): degrees to turn it clockwise so it reads upright.
 */
export async function detectRotations(o: { apiKey: string; model: string; images: string[]; signal?: AbortSignal }): Promise<number[]> {
  const content: Content[] = []
  o.images.forEach((url, i) => {
    content.push({ type: 'text', text: `Cover ${i}:` })
    content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: url.slice(url.indexOf(',') + 1) } })
  })
  content.push({
    type: 'text',
    text: `Each image above is a photo of one front cover (book, comic, board game, DVD or CD), numbered from 0. Some were taken sideways or upside down. For every cover give index and rotation: how many degrees the image must be turned clockwise so its title and picture are upright (0 if it already is; 90, 180 or 270 otherwise). Judge by the title text and the picture, not by the shape of the image.`,
  })
  const parsed = await ask<{ covers: { index: number; rotation: number }[] }>(o, content, ROTATION_SCHEMA, 'too many covers at once')
  const out = o.images.map(() => 0)
  for (const c of parsed.covers) if (c.index >= 0 && c.index < out.length && [0, 90, 180, 270].includes(c.rotation)) out[c.index] = c.rotation
  return out
}
