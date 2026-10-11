package app.mybib.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private val accents = mapOf(
    "àáâãäåāăą" to 'a', "çćĉċč" to 'c', "ďđ" to 'd', "èéêëēĕėęě" to 'e', "ĝğġģ" to 'g', "ĥħ" to 'h', "ìíîïĩīĭįı" to 'i', "ĵ" to 'j', "ķ" to 'k',
    "ĺļľŀł" to 'l', "ñńņňŉ" to 'n', "òóôõöøōŏő" to 'o', "ŕŗř" to 'r', "śŝşšș" to 's', "ţťŧț" to 't', "ùúûüũūŭůűų" to 'u', "ŵ" to 'w', "ýÿŷ" to 'y', "źżž" to 'z',
)
private val accentMap: Map<Char, Char> = accents.flatMap { (chars, to) -> chars.map { it to to } }.toMap()
private val nonWord = Regex("""[^\p{L}\p{N}]+""")

/** Lower-case, strip accents and punctuation – for search and duplicate detection. */
fun fold(s: String): String {
    val low = s.lowercase().replace("ß", "ss").replace("æ", "ae").replace("œ", "oe")
    val folded = buildString { for (ch in low) append(accentMap[ch] ?: ch) }
    return folded.replace(nonWord, " ").trim()
}

/** Probable duplicate: same ISBN, or same title + first creator (or both unknown) + volume. */
fun findDuplicate(
    items: List<Item>,
    title: String,
    isbn: String? = null,
    creators: List<String> = emptyList(),
    volume: String? = null,
    kind: String? = null,
    format: String? = null,
): Item? {
    if (!isbn.isNullOrEmpty()) items.firstOrNull { it.isbn == isbn }?.let { return it }
    val t = fold(title)
    if (t.isEmpty()) return null
    val c = creators.firstOrNull()?.let(::fold) ?: ""
    val v = volume?.let(::fold) ?: ""
    return items.firstOrNull { i ->
        fold(i.title) == t &&
            (i.creators.firstOrNull()?.let(::fold) ?: "") == c &&
            (i.volume?.let(::fold) ?: "") == v &&
            (kind == null || i.kind == kind) &&
            (format == null || i.format == format)
    }
}

fun findDuplicateOf(items: List<Item>, d: Item) =
    findDuplicate(items, title = d.title, isbn = d.isbn, creators = d.creators, volume = d.volume, kind = d.kind, format = d.format)

data class Filters(
    val q: String = "",
    /** "all" or a kind */
    val kind: String = "all",
    val status: String = "all",
    /** all / owned / wish / lent / recommend / check */
    val scope: String = "all",
    val format: String = "all",
    /** "all", "" = no room, or a room */
    val room: String = "all",
    /** "all", "" = no category, or a category */
    val category: String = "all",
    val minRating: Int = 0,
) {
    val extraActive get() = listOf(status != "all", format != "all", room != "all", category != "all", minRating > 0).count { it }
}

fun searchText(i: Item) =
    fold((listOf(i.title, i.subtitle) + i.creators + listOf(i.series, i.publisher, i.isbn, i.notes) + i.tags + listOf(i.room)).filterNotNull().joinToString(" "))

fun applyFilters(items: List<Item>, f: Filters): List<Item> {
    val words = fold(f.q).split(" ").filter { it.isNotEmpty() }
    return items.filter { i ->
        if (f.kind != "all" && i.kind != f.kind) return@filter false
        if (f.status != "all" && i.status != f.status) return@filter false
        if (f.format != "all" && i.format != f.format) return@filter false
        if (f.room != "all" && (i.room ?: "") != f.room) return@filter false
        if (f.category != "all" && (i.category ?: "") != f.category) return@filter false
        if (f.minRating > 0 && i.rating < f.minRating) return@filter false
        val inScope = when (f.scope) {
            "owned" -> i.owned
            "wish" -> !i.owned
            "lent" -> i.openLoan != null
            "recommend" -> i.recommend
            "check" -> i.needsCheck
            else -> true
        }
        if (!inScope) return@filter false
        if (words.isNotEmpty()) {
            val hay = searchText(i)
            if (!words.all { hay.contains(it) }) return@filter false
        }
        true
    }
}

private val articles = Regex("""^(der|die|das|ein|eine|the|a|an|le|la|les|el|los|las)\s+""", RegexOption.IGNORE_CASE)

/** Sort key for titles: ignore leading articles so "Der Koran" sorts under K. */
fun titleKey(t: String) = fold(t.replaceFirst(articles, ""))

private val bracketed = Regex("""\([^)]*\)""")
private val spaces = Regex("""\s+""")

/** Surname key: "Mai Thi Nguyen-Kim" → "nguyen kim", "Laura Lamping (Hg.)" → "lamping", "Schami, Rafik" → "schami". */
fun creatorKey(i: Item): String {
    val c = (i.creators.firstOrNull() ?: "").replace(bracketed, "").trim()
    val surname = if (',' in c) c.split(',').first() else c.split(spaces).last()
    return "${fold(surname)} ${titleKey(i.title)}"
}

private val chunks = Regex("""(\d+)|(\D+)""")

/** Numbers inside strings compare by value ("Band 2" < "Band 10"). */
fun natural(a: String, b: String): Int {
    val ma = chunks.findAll(a).map { it.value }.toList()
    val mb = chunks.findAll(b).map { it.value }.toList()
    for (k in 0 until minOf(ma.size, mb.size)) {
        val x = ma[k]
        val y = mb[k]
        val nx = x.toLongOrNull()
        val ny = y.toLongOrNull()
        val c = if (nx != null && ny != null) nx.compareTo(ny) else x.compareTo(y)
        if (c != 0) return c
    }
    return ma.size.compareTo(mb.size)
}

val sortKeys = listOf("title", "creator", "added", "rating", "year", "place")

fun sortItems(items: List<Item>, key: String): List<Item> {
    val byTitle = Comparator<Item> { a, b ->
        val c = natural(titleKey(a.title), titleKey(b.title))
        if (c != 0) c else natural(a.volume ?: "", b.volume ?: "")
    }
    return when (key) {
        "creator" -> items.sortedWith { a, b -> natural(creatorKey(a), creatorKey(b)) }
        "added" -> items.sortedWith { a, b -> b.addedAt.compareTo(a.addedAt) }
        "rating" -> items.sortedWith { a, b -> if (b.rating != a.rating) b.rating - a.rating else byTitle.compare(a, b) }
        "year" -> items.sortedWith { a, b -> (b.year ?: 0) - (a.year ?: 0) }
        "place" -> items.sortedWith { a, b ->
            val c = natural(fold(a.room ?: "￿"), fold(b.room ?: "￿"))
            if (c != 0) c else byTitle.compare(a, b)
        }
        else -> items.sortedWith(byTitle)
    }
}

/** Rooms with item counts ("" = not set); only owned physical items have a place. */
fun summarizePlaces(items: List<Item>): List<Pair<String, Int>> {
    val map = linkedMapOf<String, Int>()
    for (i in items) {
        if (!i.owned || i.format != "physical") continue
        map[i.room ?: ""] = (map[i.room ?: ""] ?: 0) + 1
    }
    return map.entries.map { it.key to it.value }.sortedWith { a, b ->
        if (a.first.isEmpty()) 1 else if (b.first.isEmpty()) -1 else natural(fold(a.first), fold(b.first))
    }
}

/** Rooms to offer: the configured ones (or defaults) plus any used by items. */
fun allRooms(items: List<Item>, configured: List<String>, defaults: List<String>): List<String> {
    val list = configured.ifEmpty { defaults }.toMutableList()
    for (i in items) if (i.room != null && i.room !in list) list += i.room
    return list
}

/** Names used in earlier loans, most recent first. */
fun knownPeople(items: List<Item>): List<String> =
    items.flatMap { it.loans }.sortedWith { a, b -> b.since.compareTo(a.since) }.map { it.to }.distinct()

// ---------- import / export ----------

fun toExport(items: List<Item>): JsonObject = objOf(
    "app" to "mybib",
    "version" to 1,
    "exportedAt" to nowIso(),
    "items" to items.map { it.toJson() },
)

class ImportFile(val items: List<Item>, val updateOnly: Boolean)

class ImportException(message: String) : Exception(message)

private infix fun JsonElement?.or(b: JsonElement?): JsonElement? = if (isNull) b else this

/**
 * Read an import file: a mybib export, a bare list of items, or `{ items: [...] }` (the format
 * the Claude skill produces). A top-level room applies to items without their own.
 * `"updateOnly": true` only completes books already in the catalogue.
 */
fun parseImportFile(text: String): ImportFile {
    val data = parseJson(text)
    val list = (data as? JsonArray) ?: data.obj?.get("items").arr ?: JsonArray(emptyList())
    if (list.isEmpty()) throw ImportException("no items")
    val top = data.obj ?: JsonObject(emptyMap())
    val isExport = top["app"].string == "mybib"
    val items = list.mapNotNull { it.obj }.filter { it["title"].string != null }.map { x ->
        normalizeItem(x + draftOf(
            "room" to (x["room"] or top["room"]),
            "shelf" to (x["shelf"] or (if (!x["room"].isNull) null else top["shelf"])),
            "source" to (if (isExport) x["source"] else "import"),
        ))
    }
    return ImportFile(items, top["updateOnly"].isTrue)
}

private val fillable = listOf("subtitle", "publisher", "year", "isbn", "language", "series", "volume", "pages", "description", "coverUrl", "category", "room", "ageFrom", "needsCheck")

private fun JsonElement?.isBlankValue() = isNull || string == ""

/** Copy of [old] with its empty fields filled from [inc], or null when nothing changes. */
fun fillEmpty(old: Item, inc: Item): Item? {
    val o = old.toJson()
    val n = inc.toJson()
    val patch = linkedMapOf<String, JsonElement>()
    for (k in fillable) {
        if (o[k].isBlankValue() && !n[k].isBlankValue()) patch[k] = n[k]!!
    }
    if (old.tags.isEmpty() && inc.tags.isNotEmpty()) patch["tags"] = j(inc.tags)
    if (patch.isEmpty()) return null
    return old.copyWith(patch + ("updatedAt" to JsonPrimitive(nowIso())))
}

data class MergeResult(val items: List<Item>, val added: Int, val updated: Int, val skipped: Int)

/**
 * Merge imported items: same id → newer `updatedAt` wins; obvious duplicate → its empty fields
 * are filled in; otherwise added (unless [updateOnly]).
 */
fun mergeItems(existing: List<Item>, incoming: List<Item>, updateOnly: Boolean = false): MergeResult {
    val all = existing.toMutableList()
    val idx = all.withIndex().associate { (k, i) -> i.id to k }.toMutableMap()
    var added = 0
    var updated = 0
    var skipped = 0
    for (inc in incoming) {
        val k = idx[inc.id]
        if (k != null) {
            if (inc.updatedAt > all[k].updatedAt) {
                all[k] = inc
                updated++
            } else {
                skipped++
            }
            continue
        }
        val dup = findDuplicateOf(all, inc)
        if (dup != null) {
            val filled = fillEmpty(dup, inc)
            if (filled != null) {
                all[idx.getValue(dup.id)] = filled
                updated++
            } else {
                skipped++
            }
            continue
        }
        if (updateOnly) {
            skipped++
            continue
        }
        idx[inc.id] = all.size
        all += inc
        added++
    }
    return MergeResult(all, added, updated, skipped)
}

private val csvColumns = listOf("kind", "title", "subtitle", "creators", "publisher", "year", "isbn", "language", "series", "volume", "format", "owned", "status", "rating", "recommend", "category", "room", "lentTo", "tags", "notes", "addedAt")
private val csvSpecial = Regex("""[";\n]""")

private fun JsonElement.text(): String = (this as? JsonPrimitive)?.content ?: toString()

/** Spreadsheet-friendly export (semicolon separated, as Excel in German locale expects). */
fun toCSV(items: List<Item>): String {
    fun esc(v: JsonElement?): String {
        val s = when {
            v.isNull -> ""
            v is JsonArray -> v.joinToString(", ") { it.text() }
            else -> v!!.text()
        }
        return if (csvSpecial.containsMatchIn(s)) "\"${s.replace("\"", "\"\"")}\"" else s
    }
    val rows = items.map { i ->
        val o = i.toJson()
        csvColumns.joinToString(";") { c -> esc(if (c == "lentTo") j(i.openLoan?.to) else o[c]) }
    }
    return "﻿" + (listOf(csvColumns.joinToString(";")) + rows).joinToString("\n")
}

// ---------- bulk completion ----------

/** Details online sources can deliver that are still missing. */
fun missingInfo(i: Item): List<String> = buildList {
    if (!i.hasCover) add("cover")
    if (i.publisher == null) add("publisher")
    if (i.year == null) add("year")
    if (i.isbn == null) add("isbn")
    if (i.description == null) add("description")
}

/** Books that could still gain details; [retry] includes those already looked up. */
fun bulkTargets(items: List<Item>, retry: Boolean): List<Item> =
    items.filter { it.kind == "book" && missingInfo(it).isNotEmpty() && (retry || it.lookedUp == null) }

/** Stable key of a duplicate group, so "not duplicates" can be remembered (changes when the group changes). */
fun groupKey(group: List<Item>): String = group.map { it.id }.sorted().joinToString(",")

/**
 * Groups of probable duplicates: same ISBN, or same title, kind and format where author and volume match
 * or are missing on one side (e.g. the same book entered once with and once without author).
 * Groups marked "not duplicates" ([ignored] keys) are left out.
 */
fun duplicateGroups(items: List<Item>, ignored: Collection<String> = emptyList()): List<List<Item>> {
    val parent = IntArray(items.size) { it }
    fun root(n: Int): Int {
        var r = n
        while (parent[r] != r) r = parent[r]
        parent[n] = r
        return r
    }
    fun join(a: Int, b: Int) {
        parent[root(a)] = root(b)
    }
    val byIsbn = HashMap<String, Int>()
    val byTitle = LinkedHashMap<String, MutableList<Int>>()
    items.forEachIndexed { n, i ->
        val isbn = i.isbn
        if (!isbn.isNullOrEmpty()) {
            val m = byIsbn[isbn]
            if (m == null) byIsbn[isbn] = n else join(n, m)
        }
        val t = fold(i.title)
        if (t.isNotEmpty()) byTitle.getOrPut(listOf(t, i.kind, i.format).joinToString("\u0001")) { mutableListOf() }.add(n)
    }
    fun fits(a: String, b: String) = a == b || a.isEmpty() || b.isEmpty()
    fun creator(i: Item) = i.creators.firstOrNull()?.let(::fold) ?: ""
    fun volume(i: Item) = i.volume?.let(::fold) ?: ""
    for (list in byTitle.values) {
        for (x in list.indices) for (y in x + 1 until list.size) {
            val (i, j) = items[list[x]] to items[list[y]]
            if (fits(creator(i), creator(j)) && fits(volume(i), volume(j))) join(list[x], list[y])
        }
    }
    val skip = ignored.toSet()
    return items.indices.groupBy(::root).values
        .map { idx -> idx.map { items[it] } }
        .filter { it.size > 1 && groupKey(it) !in skip }
}

private val statusRank = mapOf("none" to 0, "want" to 1, "active" to 2, "done" to 3)

/** How much is filled in – the most complete entry of a group is kept when merging. */
private fun completeness(i: Item): Int =
    listOf(i.subtitle, i.publisher, i.year, i.isbn, i.language, i.series, i.volume, i.pages, i.description, i.coverUrl, i.coverData, i.category, i.room, i.notes)
        .count { it != null && it != "" } + i.creators.size + i.tags.size + i.loans.size + (if (i.rating > 0) 1 else 0)

class GroupMerge(val keep: Item, val remove: List<String>)

/**
 * Merge a duplicate group into one entry: keeps the most complete (on a tie the oldest) entry, fills its empty
 * fields from the others, and combines what is personal – best rating, furthest status, recommendation,
 * owned, notes, tags, loans.
 */
fun mergeGroup(group: List<Item>): GroupMerge {
    val sorted = group.sortedWith(compareByDescending<Item> { completeness(it) }.thenBy { it.addedAt })
    var keep = sorted.first()
    for (other in sorted.drop(1)) keep = fillEmpty(keep, other) ?: keep
    val notes = sorted.mapNotNull { it.notes?.trim()?.ifEmpty { null } }.distinct()
    keep = keep.copy(
        coverData = keep.coverData ?: sorted.firstNotNullOfOrNull { it.coverData },
        creators = keep.creators.ifEmpty { sorted.firstOrNull { it.creators.isNotEmpty() }?.creators ?: emptyList() },
        rating = sorted.maxOf { it.rating },
        status = sorted.map { it.status }.reduce { a, b -> if ((statusRank[b] ?: 0) > (statusRank[a] ?: 0)) b else a },
        recommend = sorted.any { it.recommend },
        owned = sorted.any { it.owned },
        tags = sorted.flatMap { it.tags }.distinct(),
        notes = if (notes.isEmpty()) null else notes.joinToString("\n\n"),
        loans = sorted.flatMap { it.loans }.distinctBy { it.to to it.since }.sortedBy { it.since },
        addedAt = sorted.minOf { it.addedAt },
    )
    return GroupMerge(keep, sorted.drop(1).map { it.id })
}

/**
 * Existing entry a newly recognised item probably is: same ISBN, or same title and kind where author and
 * volume match or are missing on one side (looser than [findDuplicate], for adding covers to what is there).
 */
fun findMatch(items: List<Item>, title: String, isbn: String? = null, creators: List<String> = emptyList(), volume: String? = null, kind: String? = null): Item? {
    if (!isbn.isNullOrEmpty()) items.firstOrNull { it.isbn == isbn }?.let { return it }
    val t = fold(title)
    if (t.isEmpty()) return null
    val c = creators.firstOrNull()?.let(::fold) ?: ""
    val v = volume?.let(::fold) ?: ""
    fun fits(a: String, b: String) = a == b || a.isEmpty() || b.isEmpty()
    val hits = items.filter { i ->
        fold(i.title) == t && (kind == null || i.kind == kind) &&
            fits(i.creators.firstOrNull()?.let(::fold) ?: "", c) && fits(i.volume?.let(::fold) ?: "", v)
    }
    // a printed copy is the one a cover photo belongs to
    return hits.firstOrNull { it.format == "physical" } ?: hits.firstOrNull()
}

fun findMatchOf(items: List<Item>, d: Draft) =
    findMatch(items, d["title"].string ?: "", d["isbn"].string, d["creators"].strings, d["volume"].string, d["kind"].string)

/** What a recognised item adds to an existing entry: its empty fields, the creators if none, own cover photo if none. */
fun completionPatch(old: Item, d: Draft): Draft {
    val o = old.toJson()
    val patch = linkedMapOf<String, JsonElement>()
    for (k in fillable) {
        if (k == "needsCheck" || k == "room") continue
        if (o[k].isBlankValue() && !d[k].isBlankValue()) patch[k] = d[k]!!
    }
    if (old.creators.isEmpty() && d["creators"].strings.isNotEmpty()) patch["creators"] = d["creators"]!!
    if (old.coverData == null && !d["coverData"].isBlankValue()) patch["coverData"] = d["coverData"]!!
    return patch
}

/** Fields offered for choice when merging by hand (cover = own photo and online cover together). */
val mergeFields = listOf("cover", "title", "subtitle", "creators", "series", "volume", "publisher", "year", "isbn", "language", "pages", "kind", "format", "category", "room", "description", "status", "rating")

/** Value of a merge field, for comparing and showing; "" when empty. */
fun mergeValue(i: Item, f: String): String = when (f) {
    "cover" -> i.coverData ?: i.coverUrl ?: ""
    "creators" -> i.creators.joinToString(", ")
    "rating" -> if (i.rating > 0) i.rating.toString() else ""
    "status" -> if (i.status == "none") "" else i.status
    else -> i.toJson()[f]?.let { (it as? JsonPrimitive)?.content } ?: ""
}

/** Fields where the entries of a group differ – the ones worth a choice. */
fun differingFields(group: List<Item>): List<String> = mergeFields.filter { f -> group.map { mergeValue(it, f) }.toSet().size > 1 }

/**
 * Merge with the owner's choices: [choices] maps a field to the id of the entry whose value wins.
 * Everything not chosen comes from [mergeGroup] (most complete entry, gaps filled, notes/tags/loans combined).
 */
fun mergeWithChoices(group: List<Item>, choices: Map<String, String>): GroupMerge {
    val base = mergeGroup(group)
    val patch = linkedMapOf<String, JsonElement>()
    for ((f, id) in choices) {
        val src = group.firstOrNull { it.id == id }?.toJson() ?: continue
        val fields = if (f == "cover") listOf("coverData", "coverUrl") else listOf(f)
        for (k in fields) patch[k] = src[k] ?: JsonNull
    }
    return GroupMerge(base.keep.copyWith(patch), base.remove)
}

/**
 * Similar entries: same title and kind, but author, volume or format differ (e.g. two volumes, or one
 * entry with a typo in the author). Not duplicates for sure – shown separately so they can be merged by hand.
 */
fun similarGroups(items: List<Item>, ignored: Collection<String> = emptyList(), exclude: Set<String> = emptySet()): List<List<Item>> {
    val skip = ignored.toSet()
    return items.filter { it.id !in exclude && fold(it.title).isNotEmpty() }
        .groupBy { fold(it.title) + "\u0001" + it.kind }.values
        .filter { it.size > 1 && groupKey(it) !in skip }
}
