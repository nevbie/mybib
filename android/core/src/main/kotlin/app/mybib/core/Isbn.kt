package app.mybib.core

private val notCode = Regex("[^0-9X]")
private val innerX = Regex("X(?=.)")

/** Strip everything but digits (and a trailing X of an ISBN-10). */
fun cleanCode(raw: String) = raw.uppercase().replace(notCode, "").replace(innerX, "")

fun isValidIsbn10(s: String): Boolean {
    if (!Regex("""^\d{9}[\dX]$""").matches(s)) return false
    val sum = (0 until 10).sumOf { i -> (if (s[i] == 'X') 10 else s[i].digitToInt()) * (10 - i) }
    return sum % 11 == 0
}

private fun eanCheck(digits12: String) = (10 - (0 until 12).sumOf { i -> digits12[i].digitToInt() * (if (i % 2 == 1) 3 else 1) } % 10) % 10

/** EAN-13 checksum – ISBN-13 is an EAN-13 starting with 978/979. */
fun isValidEan13(s: String) = Regex("""^\d{13}$""").matches(s) && eanCheck(s) == s[12].digitToInt()

fun isIsbn13(s: String) = isValidEan13(s) && (s.startsWith("978") || s.startsWith("979"))

fun isbn10to13(s: String): String {
    val core = "978${s.substring(0, 9)}"
    return "$core${eanCheck(core)}"
}

data class Code(val type: String, val code: String)

/** Classify a scanned or typed code: "isbn" (normalised to 13 digits), "ean" or null (invalid). */
fun classifyCode(raw: String): Code? {
    val s = cleanCode(raw)
    if (s.length == 10 && isValidIsbn10(s)) return Code("isbn", isbn10to13(s))
    if (s.length == 13 && isIsbn13(s)) return Code("isbn", s)
    if (s.length == 13 && isValidEan13(s)) return Code("ean", s)
    // UPC-A (12 digits) – common on US CDs / DVDs
    if (s.length == 12 && isValidEan13("0$s")) return Code("ean", s)
    if (s.length == 8 && s.all { it.isDigit() }) return Code("ean", s)
    return null
}
