package app.mybib.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.roundToLong
import kotlin.random.Random

/** What kind of thing sits on the shelf. */
val kinds = listOf("book", "game", "dvd", "cd")

/** Physical copy, e-book or audiobook (only meaningful for books). */
val formats = listOf("physical", "ebook", "audio")

/** Reading (playing, watching, listening) status. `want` = want to read, `done` = read. */
val statuses = listOf("none", "want", "active", "done")

val sources = listOf("manual", "isbn", "search", "ai", "import")

data class Loan(
    val to: String,
    /** ISO date YYYY-MM-DD */
    val since: String,
    /** ISO date when it came back; null while it is still lent out */
    val returned: String? = null,
) {
    fun toJson(): JsonObject = objOf("to" to to, "since" to since, "returned" to returned)
}

fun today(): String = LocalDate.now().toString()

private val isoMillis = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

/** UTC timestamp like JavaScript's toISOString(). */
fun nowIso(): String = isoMillis.format(Instant.now())

fun newId(): String =
    System.currentTimeMillis().toString(36) + (1..6).joinToString("") { Random.nextInt(36).toString(36) }

/** One catalogue entry. Same JSON format as the web app, so backups move between both. */
data class Item(
    val id: String,
    val kind: String,
    val title: String,
    val subtitle: String? = null,
    /** authors, artists, directors or game designers */
    val creators: List<String> = emptyList(),
    val publisher: String? = null,
    val year: Int? = null,
    /** ISBN-13 for books, EAN / UPC for everything else */
    val isbn: String? = null,
    val language: String? = null,
    val series: String? = null,
    val volume: String? = null,
    val pages: Int? = null,
    val description: String? = null,
    /** remote cover (Open Library, Google Books, Cover Art Archive) */
    val coverUrl: String? = null,
    /** own photo, downscaled JPEG data URL – wins over coverUrl */
    val coverData: String? = null,
    val tags: List<String> = emptyList(),
    /** one main category: a default id (see Categories.kt) or an own name */
    val category: String? = null,
    val format: String = "physical",
    /** false = wishlist (not owned yet) */
    val owned: Boolean = true,
    val status: String = "none",
    /** 0 = not rated, 1–5 stars */
    val rating: Int = 0,
    val recommend: Boolean = false,
    val notes: String? = null,
    val room: String? = null,
    val playersMin: Int? = null,
    val playersMax: Int? = null,
    val playMinutes: Int? = null,
    val ageFrom: Int? = null,
    /** all loans, newest last; the open one has no `returned` */
    val loans: List<Loan> = emptyList(),
    /** set by the photo recognition when it is unsure – shown as "please check" */
    val needsCheck: Boolean = false,
    /** date of the last automatic online lookup, so bulk completion doesn't retry every time */
    val lookedUp: String? = null,
    val source: String = "manual",
    val addedAt: String,
    val updatedAt: String,
) {
    val openLoan: Loan? get() = loans.firstOrNull { it.returned == null }

    val hasCover get() = coverData != null || coverUrl != null

    fun toJson(): JsonObject = objOf(
        "id" to id,
        "kind" to kind,
        "title" to title,
        "subtitle" to subtitle,
        "creators" to creators,
        "publisher" to publisher,
        "year" to year,
        "isbn" to isbn,
        "language" to language,
        "series" to series,
        "volume" to volume,
        "pages" to pages,
        "description" to description,
        "coverUrl" to coverUrl,
        "coverData" to coverData,
        "tags" to tags,
        "category" to category,
        "format" to format,
        "owned" to owned,
        "status" to status,
        "rating" to rating,
        "recommend" to recommend,
        "notes" to notes,
        "room" to room,
        "playersMin" to playersMin,
        "playersMax" to playersMax,
        "playMinutes" to playMinutes,
        "ageFrom" to ageFrom,
        "loans" to loans.map { it.toJson() },
        "needsCheck" to (if (needsCheck) true else null),
        "lookedUp" to lookedUp,
        "source" to source,
        "addedAt" to addedAt,
        "updatedAt" to updatedAt,
    )

    /** Change some fields; a key mapped to null removes that optional value. */
    fun copyWith(patch: Draft): Item = normalizeItem(toJson() + patch)

    fun copyWith(vararg patch: Pair<String, Any?>): Item = copyWith(draftOf(*patch))
}

private fun str(v: JsonElement?): String? = v.string?.trim()?.ifEmpty { null } ?: v.numberText

private fun int(v: JsonElement?): Int? {
    v.string?.let { return it.trim().toIntOrNull() }
    val n = v.numberText ?: return null
    n.toIntOrNull()?.let { return it }
    val d = n.toDoubleOrNull() ?: return null
    if (!d.isFinite()) return null
    // Dart's round(): half away from zero
    val r = (if (d < 0) -abs(d).roundToLong() else d.roundToLong())
    return r.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
}

private val listSplit = Regex("""\s*[;/]\s*|\s+&\s+""")

private fun strList(v: JsonElement?): List<String> {
    if (v is JsonArray) return v.mapNotNull(::str)
    val s = v.string
    if (s != null && s.isNotBlank()) return s.split(listSplit).map { it.trim() }.filter { it.isNotEmpty() }
    return emptyList()
}

private fun oneOf(list: List<String>, v: JsonElement?, fallback: String) = v.string?.takeIf { it in list } ?: fallback

/** Dart's `a ?? b` for JSON values: null and missing both fall through. */
private infix fun JsonElement?.or(b: JsonElement?): JsonElement? = if (isNull) b else this

/**
 * Only rooms are kept. Older data may still carry a shelf: the photo import put everything
 * in room "Foto-Import" with shelves "Foto 1" … – those shelves become rooms.
 */
private fun roomOf(r: Draft): String? {
    val room = str(r["room"])
    val shelf = str(r["shelf"])
    if (shelf != null && (room == null || room == "Foto-Import")) return shelf
    return room
}

private val notIsbn = Regex("[^0-9Xx]")

/**
 * Turn anything that looks roughly like an item (form draft, AI result, imported JSON)
 * into a complete, valid Item. Unknown fields are dropped.
 */
fun normalizeItem(r: Draft, now: String? = null): Item {
    val at = now ?: nowIso()
    val loans = r["loans"].arr?.mapNotNull { l ->
        val m = l.obj ?: return@mapNotNull null
        val to = str(m["to"]) ?: return@mapNotNull null
        Loan(to, str(m["since"]) ?: today(), str(m["returned"]))
    } ?: emptyList()
    val coverData = r["coverData"].string
    val isbn = str(r["isbn"])?.replace(notIsbn, "")
    return Item(
        id = str(r["id"]) ?: newId(),
        kind = oneOf(kinds, r["kind"], "book"),
        title = str(r["title"]) ?: "?",
        subtitle = str(r["subtitle"]),
        creators = strList(r["creators"] or r["authors"] or r["author"]),
        publisher = str(r["publisher"]),
        year = int(r["year"]),
        isbn = isbn?.ifEmpty { null },
        language = str(r["language"]),
        series = str(r["series"]),
        volume = str(r["volume"]),
        pages = int(r["pages"]),
        description = str(r["description"]),
        coverUrl = str(r["coverUrl"]),
        coverData = coverData?.takeIf { it.startsWith("data:image/") },
        tags = strList(r["tags"]),
        category = toCategory(str(r["category"])),
        format = oneOf(formats, r["format"], "physical"),
        owned = !r["owned"].isFalse,
        status = oneOf(statuses, r["status"], "none"),
        rating = (int(r["rating"]) ?: 0).coerceIn(0, 5),
        recommend = r["recommend"].isTrue,
        notes = str(r["notes"]),
        room = roomOf(r),
        playersMin = int(r["playersMin"]),
        playersMax = int(r["playersMax"]),
        playMinutes = int(r["playMinutes"]),
        ageFrom = int(r["ageFrom"]),
        loans = loans,
        needsCheck = r["needsCheck"].isTrue,
        lookedUp = str(r["lookedUp"]),
        source = oneOf(sources, r["source"], "manual"),
        addedAt = str(r["addedAt"]) ?: at,
        updatedAt = str(r["updatedAt"]) ?: at,
    )
}

fun normalizeItem(vararg pairs: Pair<String, Any?>, now: String? = null) = normalizeItem(draftOf(*pairs), now)

data class Settings(
    val claudeKey: String = "",
    val claudeModel: String = "claude-opus-5-5",
    val googleBooksKey: String = "",
    val lastRoom: String = "",
    /** rooms shown even when empty; [] = the default rooms */
    val rooms: List<String> = emptyList(),
    /** category list in display order; [] = the default categories */
    val categories: List<String> = emptyList(),
    /** "de" or "en"; null = phone language */
    val lang: String? = null,
) {
    fun toJson(): JsonObject = objOf(
        "claudeKey" to claudeKey,
        "claudeModel" to claudeModel,
        "googleBooksKey" to googleBooksKey,
        "lastRoom" to lastRoom,
        "rooms" to rooms,
        "categories" to categories,
        "lang" to lang,
    )

    companion object {
        fun fromJson(j: JsonObject) = Settings(
            claudeKey = str(j["claudeKey"]) ?: "",
            claudeModel = str(j["claudeModel"]) ?: "claude-opus-5-5",
            googleBooksKey = str(j["googleBooksKey"]) ?: "",
            lastRoom = str(j["lastRoom"]) ?: "",
            rooms = strList(j["rooms"]),
            categories = strList(j["categories"]),
            lang = str(j["lang"]),
        )
    }
}

val defaultRooms = listOf(
    listOf("Küche", "Kitchen"),
    listOf("Wohnzimmer", "Living room"),
    listOf("Kleines Zimmer", "Small room"),
)

fun defaultRoomNames(lang: String) = defaultRooms.map { it[if (lang == "de") 0 else 1] }

