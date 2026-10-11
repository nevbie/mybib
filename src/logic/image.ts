/** Downscale a photo in the browser. Returns a JPEG data URL. */
export async function resizeImage(file: Blob, maxEdge: number, quality = 0.85): Promise<string> {
  const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' })
  const scale = Math.min(1, maxEdge / Math.max(bmp.width, bmp.height))
  const w = Math.round(bmp.width * scale)
  const h = Math.round(bmp.height * scale)
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  canvas.getContext('2d')!.drawImage(bmp, 0, 0, w, h)
  bmp.close()
  return canvas.toDataURL('image/jpeg', quality)
}

export function dataUrlBase64(dataUrl: string): string {
  return dataUrl.slice(dataUrl.indexOf(',') + 1)
}

/** Small cover thumbnail kept with the item (≈ 20–40 KB). */
export const coverFromPhoto = (file: Blob) => resizeImage(file, 480, 0.8)

/** Photo sent to Claude for recognition – large enough to read small spine print. */
export const photoForAI = (file: Blob) => resizeImage(file, 2400, 0.88)

/**
 * Cut one cover out of a photo with several (box in thousandths of width/height, as Claude reports it),
 * with a small margin, as a cover thumbnail. Returns null when the box is unusable.
 */
export async function cropCover(dataUrl: string, box: { x0: number; y0: number; x1: number; y1: number }): Promise<string | null> {
  const img = new Image()
  img.src = dataUrl
  await img.decode()
  const clamp = (v: number) => Math.min(1, Math.max(0, v / 1000))
  const pad = 0.01
  const x0 = clamp(Math.min(box.x0, box.x1)) - pad
  const y0 = clamp(Math.min(box.y0, box.y1)) - pad
  const x1 = clamp(Math.max(box.x0, box.x1)) + pad
  const y1 = clamp(Math.max(box.y0, box.y1)) + pad
  const sx = Math.max(0, x0) * img.naturalWidth
  const sy = Math.max(0, y0) * img.naturalHeight
  const sw = (Math.min(1, x1) - Math.max(0, x0)) * img.naturalWidth
  const sh = (Math.min(1, y1) - Math.max(0, y0)) * img.naturalHeight
  if (sw < 20 || sh < 20) return null
  const scale = Math.min(1, 480 / Math.max(sw, sh))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(sw * scale)
  canvas.height = Math.round(sh * scale)
  canvas.getContext('2d')!.drawImage(img, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height)
  return canvas.toDataURL('image/jpeg', 0.8)
}
