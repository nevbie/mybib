/** Strip everything but digits (and a trailing X of an ISBN-10). */
export function cleanCode(raw: string): string {
  return raw.toUpperCase().replace(/[^0-9X]/g, '').replace(/X(?=.)/g, '')
}

export function isValidIsbn10(s: string): boolean {
  if (!/^\d{9}[\dX]$/.test(s)) return false
  let sum = 0
  for (let i = 0; i < 10; i++) sum += (s[i] === 'X' ? 10 : Number(s[i])) * (10 - i)
  return sum % 11 === 0
}

/** EAN-13 checksum – ISBN-13 is an EAN-13 starting with 978/979. */
export function isValidEan13(s: string): boolean {
  if (!/^\d{13}$/.test(s)) return false
  let sum = 0
  for (let i = 0; i < 12; i++) sum += Number(s[i]) * (i % 2 ? 3 : 1)
  return (10 - (sum % 10)) % 10 === Number(s[12])
}

export function isIsbn13(s: string): boolean {
  return isValidEan13(s) && (s.startsWith('978') || s.startsWith('979'))
}

export function isbn10to13(s: string): string {
  const core = '978' + s.slice(0, 9)
  let sum = 0
  for (let i = 0; i < 12; i++) sum += Number(core[i]) * (i % 2 ? 3 : 1)
  return core + ((10 - (sum % 10)) % 10)
}

export type CodeInfo = { type: 'isbn'; code: string } | { type: 'ean'; code: string } | { type: 'invalid' }

/** Classify a scanned or typed code: ISBN (normalised to 13 digits), other EAN/UPC, or nonsense. */
export function classifyCode(raw: string): CodeInfo {
  const s = cleanCode(raw)
  if (s.length === 10 && isValidIsbn10(s)) return { type: 'isbn', code: isbn10to13(s) }
  if (s.length === 13 && isIsbn13(s)) return { type: 'isbn', code: s }
  if (s.length === 13 && isValidEan13(s)) return { type: 'ean', code: s }
  // UPC-A (12 digits) – common on US CDs / DVDs
  if (s.length === 12 && isValidEan13('0' + s)) return { type: 'ean', code: s }
  if (s.length === 8 && /^\d+$/.test(s)) return { type: 'ean', code: s }
  return { type: 'invalid' }
}
