package app.mybib.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.net.URLEncoder

/** An online search result: item fields plus the service it came from. */
class Candidate(val data: JsonObject, val via: String) {
    val title get() = data["title"].string ?: ""
    val creators get() = data["creators"].strings
    val coverUrl get() = data["coverUrl"].string
    val kind get() = data["kind"].string ?: "book"

    fun withData(patch: Draft) = Candidate(data.merge(patch), via)
    fun withData(vararg patch: Pair<String, Any?>) = withData(draftOf(*patch))
}

private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

private fun year(s: String?): Int? = Regex("""\d{4}""").find(s ?: "")?.value?.toInt()

/** Fill gaps in [a] with values from [b] (same book from a second service). */
fun mergeCandidate(a: Candidate, b: Candidate): Candidate {
    val out = LinkedHashMap<String, JsonElement>(a.data)
    b.data.forEach { (k, v) -> if (out[k].isEmptyValue()) out[k] = v }
    return Candidate(JsonObject(out), if (a.via == b.via) a.via else "${a.via} + ${b.via}")
}

private fun words(s: String) = fold(s).split(" ").filter { it.length > 1 }.toSet()

/** How well does an online result match what we know (e.g. from a spine photo)? 0…1 */
fun matchScore(title: String, creators: List<String>, c: Candidate): Double {
    val a = words(title)
    val b = words("${c.title} ${c.data["subtitle"].string ?: ""}")
    if (a.isEmpty()) return 0.0
    var score = a.count { it in b }.toDouble() / a.size
    if (creators.isNotEmpty()) {
        val last = fold(creators.first()).split(" ").last()
        val has = c.creators.any { fold(it).contains(last) }
        score = score * 0.7 + (if (has) 0.3 else 0.0)
    }
    return score
}

/** Share of words the two titles have in common (Jaccard), 0…1. */
fun titleOverlap(a: String, b: String): Double {
    val x = fold(a).split(" ").filter { it.isNotEmpty() }.toSet()
    val y = fold(b).split(" ").filter { it.isNotEmpty() }.toSet()
    if (x.isEmpty() || y.isEmpty()) return 0.0
    val common = x.count { it in y }
    return common.toDouble() / (x.size + y.size - common)
}

/** Fill only the fields the item doesn't have yet from an online result. */
fun enrichPatch(item: Map<String, JsonElement>, c: Candidate): Draft {
    val patch = linkedMapOf<String, JsonElement>()
    for (k in listOf("subtitle", "publisher", "year", "isbn", "pages", "description", "coverUrl", "language")) {
        if (item[k].isEmptyValue() && !c.data[k].isEmptyValue()) patch[k] = c.data[k]!!
    }
    if (item["creators"].isEmptyValue() && c.creators.isNotEmpty()) patch["creators"] = j(c.creators)
    return patch
}

/** Item draft (JSON map) from a candidate, ready for normalizeItem / the form. */
fun candidateDraft(c: Candidate, source: String = "search"): Draft = c.data + draftOf("source" to source)

/** Google Books, Open Library, MusicBrainz + Cover Art Archive and UPCitemdb. */
class Lookup(private val http: Http = UrlConnectionHttp()) {
    private val timeoutMs = 12_000

    /** Last problem Google Books reported: "" = fine, "quota" = daily limit reached, "key" = key rejected. */
    @Volatile private var googleProblem = ""

    fun takeGoogleProblem(): String {
        val p = googleProblem
        googleProblem = ""
        return p
    }

    private suspend fun getJson(url: String): Pair<Int, JsonElement?> = withContext(Dispatchers.IO) {
        try {
            val res = http.send(HttpRequest("GET", url, mapOf("User-Agent" to "mybib/1.0 (https://github.com/nevbie/mybib)"), timeoutMs = timeoutMs))
            if (res.status != 200) res.status to null else 200 to parseJson(res.text)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            0 to null
        }
    }

    /** True when the URL is a real image (Open Library / Cover Art Archive answer 404 for "no cover"). */
    suspend fun probeImage(url: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val res = http.send(HttpRequest("HEAD", url, timeoutMs = timeoutMs))
            val type = res.headers["content-type"] ?: ""
            val len = res.headers["content-length"]?.toIntOrNull() ?: 1000
            res.status == 200 && type.startsWith("image/") && len > 200
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
    }

    // ---------- Google Books ----------

    private fun fromGoogle(v: JsonObject): Candidate? {
        val i = v["volumeInfo"].obj ?: return null
        val title = i["title"].string ?: return null
        var isbn: String? = null
        i["industryIdentifiers"].arr?.forEach { x -> if (x.obj?.get("type").string == "ISBN_13") isbn = x.obj?.get("identifier").string }
        val links = i["imageLinks"].obj
        val thumb = links?.get("thumbnail").string ?: links?.get("smallThumbnail").string
        val pages = i["pageCount"].int
        return Candidate(objOf(
            "kind" to "book",
            "title" to title,
            "subtitle" to i["subtitle"],
            "creators" to i["authors"].strings,
            "publisher" to i["publisher"],
            "year" to year(i["publishedDate"].string),
            "description" to i["description"],
            "pages" to (if (pages != null && pages > 0) pages else null),
            "language" to i["language"],
            "isbn" to isbn,
            "coverUrl" to thumb?.replaceFirst("http:", "https:")?.replace("&edge=curl", ""),
        ), "Google Books")
    }

    private suspend fun google(q: String, key: String, max: Int = 8): List<Candidate> {
        val url = "https://www.googleapis.com/books/v1/volumes?q=${enc(q)}&maxResults=$max&printType=books${if (key.isNotEmpty()) "&key=${enc(key)}" else ""}"
        val (status, data) = getJson(url)
        if (status == 429) googleProblem = "quota"
        if ((status == 400 || status == 403) && key.isNotEmpty()) googleProblem = "key"
        return data.obj?.get("items").arr?.mapNotNull { it.obj?.let(::fromGoogle) } ?: emptyList()
    }

    // ---------- Open Library ----------

    private suspend fun openLibraryIsbn(isbn: String): Candidate? {
        val (_, data) = getJson("https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&format=json&jscmd=data")
        val b = data.obj?.get("ISBN:$isbn").obj ?: return null
        val title = b["title"].string ?: return null
        val cover = b["cover"].obj
        return Candidate(objOf(
            "kind" to "book",
            "title" to title,
            "subtitle" to b["subtitle"],
            "creators" to (b["authors"].arr?.mapNotNull { it.obj?.get("name").string } ?: emptyList()),
            "publisher" to b["publishers"].arr?.firstNotNullOfOrNull { it.obj }?.get("name"),
            "year" to year(b["publish_date"].string),
            "pages" to b["number_of_pages"],
            "isbn" to isbn,
            "coverUrl" to (cover?.get("medium") ?: cover?.get("large")),
        ), "Open Library")
    }

    private suspend fun openLibrarySearch(params: String): List<Candidate> {
        val fields = "title,subtitle,author_name,first_publish_year,publisher,isbn,cover_i,language,number_of_pages_median"
        val (_, data) = getJson("https://openlibrary.org/search.json?$params&limit=8&fields=$fields")
        val docs = data.obj?.get("docs").arr ?: return emptyList()
        return docs.mapNotNull { it.obj }.filter { it["title"].string != null }.map { d ->
            val coverId = d["cover_i"]
            Candidate(objOf(
                "kind" to "book",
                "title" to d["title"],
                "subtitle" to d["subtitle"],
                "creators" to d["author_name"].strings,
                "year" to d["first_publish_year"],
                "publisher" to d["publisher"].arr?.firstOrNull(),
                "isbn" to d["isbn"].strings.firstOrNull { it.length == 13 && it.startsWith("97") },
                "pages" to d["number_of_pages_median"],
                "language" to d["language"].arr?.firstOrNull(),
                "coverUrl" to (if (!coverId.isNull) "https://covers.openlibrary.org/b/id/${coverId!!.let { it.numberText ?: it.string }}-M.jpg" else null),
            ), "Open Library")
        }
    }

    // ---------- MusicBrainz ----------

    private suspend fun musicbrainz(query: String): List<Candidate> {
        val (_, data) = getJson("https://musicbrainz.org/ws/2/release/?query=${enc(query)}&fmt=json&limit=8")
        val releases = data.obj?.get("releases").arr ?: return emptyList()
        return releases.mapNotNull { it.obj }.map { r ->
            val fmt = r["media"].arr?.firstNotNullOfOrNull { it.obj }?.get("format").string ?: ""
            val barcode = r["barcode"].string
            Candidate(objOf(
                "kind" to (if (Regex("dvd|blu-ray", RegexOption.IGNORE_CASE).containsMatchIn(fmt)) "dvd" else "cd"),
                "title" to r["title"],
                "creators" to (r["artist-credit"].arr?.mapNotNull { it.obj?.get("name").string } ?: emptyList()),
                "publisher" to r["label-info"].arr?.firstNotNullOfOrNull { it.obj }?.get("label").obj?.get("name"),
                "year" to year(r["date"].string),
                "isbn" to barcode?.ifEmpty { null },
                "coverUrl" to "https://coverartarchive.org/release/${r["id"].string}/front-250",
            ), "MusicBrainz")
        }
    }

    private suspend fun upcitemdb(ean: String): List<Candidate> {
        val (_, data) = getJson("https://api.upcitemdb.com/prod/trial/lookup?upc=$ean")
        val items = data.obj?.get("items").arr ?: return emptyList()
        return items.mapNotNull { it.obj }.filter { it["title"].string != null }.map { x ->
            val cat = x["category"].string ?: ""
            val kind = when {
                Regex("game|spiel", RegexOption.IGNORE_CASE).containsMatchIn(cat) -> "game"
                Regex("music|cd", RegexOption.IGNORE_CASE).containsMatchIn(cat) -> "cd"
                else -> "dvd"
            }
            Candidate(objOf(
                "kind" to kind,
                "title" to x["title"],
                "creators" to emptyList<String>(),
                "publisher" to x["brand"],
                "isbn" to ean,
                "coverUrl" to x["images"].strings.firstOrNull { it.startsWith("https:") },
            ), "UPCitemdb")
        }
    }

    // ---------- public API ----------

    suspend fun withWorkingCover(c: Candidate): Candidate {
        val url = c.coverUrl
        if (url != null && !probeImage(url)) return Candidate(JsonObject(c.data - "coverUrl"), c.via)
        return c
    }

    private suspend fun withWorkingCovers(list: List<Candidate>) = coroutineScope { list.map { async { withWorkingCover(it) } }.awaitAll() }

    /** Look up an ISBN in Google Books and Open Library, merged into one result. */
    suspend fun lookupIsbn(isbn: String, googleKey: String = ""): Candidate? {
        val (g, ol) = coroutineScope {
            val g = async { google("isbn:$isbn", googleKey, max = 1).firstOrNull() }
            val ol = async { openLibraryIsbn(isbn) }
            g.await() to ol.await()
        }
        var c = if (g != null && ol != null) {
            // Open Library covers are larger and have no "preview" banner; Google usually has the better text.
            mergeCandidate(if (ol.coverUrl != null) g.withData("coverUrl" to ol.coverUrl) else g, ol)
        } else {
            g ?: ol
        } ?: return null
        c = c.withData("isbn" to isbn)
        if (c.coverUrl == null) {
            val fallback = "https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false"
            return if (probeImage(fallback)) c.withData("coverUrl" to fallback) else c
        }
        return withWorkingCover(c)
    }

    /** Look up a non-ISBN barcode (CD, DVD, game). */
    suspend fun lookupEan(ean: String): List<Candidate> {
        val mb = musicbrainz("barcode:$ean")
        val list = mb.ifEmpty { upcitemdb(ean) }
        return withWorkingCovers(list.take(5))
    }

    /** Google Books + Open Library by title / author, merged; covers not checked yet. */
    suspend fun searchBooks(title: String, creator: String, googleKey: String = ""): List<Candidate> {
        val gq = listOfNotNull(title.ifEmpty { null }?.let { "intitle:$it" }, creator.ifEmpty { null }?.let { "inauthor:$it" }).joinToString(" ")
        val olq = listOfNotNull(title.ifEmpty { null }?.let { "title=${enc(it)}" }, creator.ifEmpty { null }?.let { "author=${enc(it)}" }).joinToString("&")
        val (g, ol) = coroutineScope {
            val g = async { google(gq, googleKey) }
            val ol = async { openLibrarySearch(olq) }
            g.await() to ol.await()
        }
        return dedupe(g + ol)
    }

    /** Free-text search by title / creator for the chosen kind. */
    suspend fun searchOnline(kind: String, title: String, creator: String, googleKey: String = ""): List<Candidate> {
        val t = title.trim()
        val c = creator.trim()
        if (t.isEmpty() && c.isEmpty()) return emptyList()
        var list = emptyList<Candidate>()
        if (kind == "book") {
            list = searchBooks(t, c, googleKey)
        } else if (kind == "cd" || kind == "dvd") {
            val q = listOfNotNull(
                t.ifEmpty { null }?.let { "release:\"${it.replace("\"", "")}\"" },
                c.ifEmpty { null }?.let { "artist:\"${it.replace("\"", "")}\"" },
            ).joinToString(" AND ")
            list = musicbrainz(q)
            if (kind == "dvd") list = list.filter { it.kind == "dvd" } + list.filter { it.kind != "dvd" }
        }
        return withWorkingCovers(list.take(10))
    }

    private fun dedupe(list: List<Candidate>): List<Candidate> {
        val out = mutableListOf<Candidate>()
        fun key(c: Candidate) = "${fold(c.title)}|${fold(c.creators.firstOrNull() ?: "")}"
        for (c in list) {
            val i = out.indexOfFirst { key(it) == key(c) }
            if (i >= 0) out[i] = mergeCandidate(out[i], c) else out += c
        }
        return out
    }

    /**
     * Best online match for a catalogued item: by ISBN if it has one, otherwise by title + author;
     * accepted only when the title (and author, if known) clearly match.
     */
    suspend fun findBestMatch(item: Item, googleKey: String = ""): Candidate? {
        if (item.isbn != null && Regex("""^97[89]\d{10}$""").matches(item.isbn)) {
            lookupIsbn(item.isbn, googleKey)?.let { return it }
        }
        val list = searchBooks(item.title, item.creators.firstOrNull() ?: "", googleKey)
        // without a known author only an (almost) identical title counts – in both directions
        val min = if (item.creators.isNotEmpty()) 0.75 else 0.95
        var best: Candidate? = null
        var bestScore = 0.0
        for (c in list) {
            val s = if (item.creators.isNotEmpty()) matchScore(item.title, item.creators, c) else titleOverlap(item.title, c.title)
            if (s > bestScore) {
                best = c
                bestScore = s
            }
        }
        return if (best != null && bestScore >= min) withWorkingCover(best) else null
    }
}
