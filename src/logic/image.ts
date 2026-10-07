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
