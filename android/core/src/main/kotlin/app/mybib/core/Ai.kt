package app.mybib.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.util.Base64

/*
 * Recognise items on a shelf photo (or a single cover) with Claude's vision.
 * The API key is the user's own, stored only on this device and sent only to api.anthropic.com.
 */

class Recognized(
    val kind: String,
    val title: String,
    val creators: List<String>,
    val series: String = "",
    val volume: String = "",
    val publisher: String = "",
    val language: String = "",
    val confidence: String = "high",
    val remark: String = "",
) {
    /** Item draft for normalizeItem / the form. */
    fun toDraft(): Draft = linkedMapOf<String, Any?>().apply {
        put("kind", kind)
        put("title", title)
        put("creators", creators)
        if (series.isNotEmpty()) put("series", series)
        if (volume.isNotEmpty()) put("volume", volume)
        if (publisher.isNotEmpty()) put("publisher", publisher)
        if (language.isNotEmpty()) put("language", language)
        if (confidence != "high") put("needsCheck", true)
        put("source", "ai")
    }.mapValuesTo(linkedMapOf()) { j(it.value) }

    companion object {
        fun fromJson(o: JsonObject) = Recognized(
            kind = o["kind"].string?.takeIf { it in kinds } ?: "book",
            title = (o["title"].string ?: "").trim(),
            creators = o["creators"].strings.map { it.trim() }.filter { it.isNotEmpty() },
            series = o["series"].string ?: "",
            volume = o["volume"].string ?: "",
            publisher = o["publisher"].string ?: "",
            language = o["language"].string ?: "",
            confidence = o["confidence"].string ?: "high",
            remark = o["remark"].string ?: "",
        )
    }
}

class RecognizeError(
    /** auth, refusal, rate, network, parse, other */
    val code: String,
    message: String,
) : Exception(message)

private val schema = buildJsonObject {
    put("type", "object")
    put("additionalProperties", false)
    putJsonArray("required") { add("items") }
    putJsonObject("properties") {
        putJsonObject("items") {
            put("type", "array")
            putJsonObject("items") {
                put("type", "object")
                put("additionalProperties", false)
                putJsonArray("required") { listOf("kind", "title", "creators", "series", "volume", "publisher", "language", "confidence", "remark").forEach { add(it) } }
                putJsonObject("properties") {
                    putJsonObject("kind") { put("type", "string"); putJsonArray("enum") { kinds.forEach { add(it) } } }
                    putJsonObject("title") { put("type", "string") }
                    putJsonObject("creators") { put("type", "array"); putJsonObject("items") { put("type", "string") } }
                    putJsonObject("series") { put("type", "string") }
                    putJsonObject("volume") { put("type", "string") }
                    putJsonObject("publisher") { put("type", "string") }
                    putJsonObject("language") { put("type", "string") }
                    putJsonObject("confidence") { put("type", "string"); putJsonArray("enum") { add("high"); add("medium"); add("low") } }
                    putJsonObject("remark") { put("type", "string") }
                }
            }
        }
    }
}

private const val PROMPT = """This photo shows part of a private home library: book spines (often vertical, sometimes upside down or lying flat), maybe also front covers, board game boxes, DVDs or CDs.

List every item whose spine or cover you can see, from left to right and top to bottom. For each item:
- kind: "book" (including comics, picture books, magazines-with-ISBN), "game" (board/card games), "dvd" (DVD/Blu-ray) or "cd" (music CDs, audio-book CDs count as "cd").
- title: exactly as printed, in the original script (keep Chinese characters as characters, German umlauts, etc.). Use the book's real title, not the series name, when both are visible.
- creators: authors / artists / directors / designers as printed (empty array if none visible). If you are confident who the author is from the title alone (a well-known book), you may add them and say so in remark.
- series and volume: e.g. "Asterix" / "36", "bpb Schriftenreihe" / "11128", Chinese multi-volume sets "金瓶梅词话" / "1".
- publisher: if visible on the spine (Reclam, dtv, Carlsen, Ravensburger, btb, Hanser …), else "".
- language: ISO 639-1 code of the item's language ("de", "en", "zh", "tr", "la", "fr" …), "" if unclear.
- confidence: "high" if clearly readable, "medium" if partly guessed, "low" if mostly guessed.
- remark: short note on what was unclear, else "".

Skip things that are not catalogue items (folders, loose papers, boxes of toys, stacks of newspapers, notebooks without a title). Do not invent items you cannot see. If a spine is too blurry to read at all, skip it rather than guessing wildly."""

/** Claude Messages API over raw HTTP. */
class Claude(private val http: Http = UrlConnectionHttp()) {
    fun requestBody(model: String, jpeg: ByteArray, hint: String): JsonObject = buildJsonObject {
        put("model", model)
        put("max_tokens", 16000)
        put("fallbacks", "default")
        putJsonObject("output_config") {
            put("effort", "medium")
            putJsonObject("format") {
                put("type", "json_schema")
                put("schema", schema)
            }
        }
        putJsonArray("messages") {
            addJsonObject {
                put("role", "user")
                putJsonArray("content") {
                    addJsonObject {
                        put("type", "image")
                        putJsonObject("source") {
                            put("type", "base64")
                            put("media_type", "image/jpeg")
                            put("data", Base64.getEncoder().encodeToString(jpeg))
                        }
                    }
                    addJsonObject {
                        put("type", "text")
                        put("text", PROMPT + (if (hint.isNotBlank()) "\n\nHint from the owner: ${hint.trim()}" else ""))
                    }
                }
            }
        }
    }

    suspend fun recognizePhoto(apiKey: String, model: String, jpeg: ByteArray, hint: String = ""): List<Recognized> {
        val body = requestBody(model, jpeg, hint).toString().encodeToByteArray()
        val res = withContext(Dispatchers.IO) {
            try {
                http.send(HttpRequest(
                    "POST",
                    "https://api.anthropic.com/v1/messages",
                    mapOf(
                        "x-api-key" to apiKey,
                        "anthropic-version" to "2023-06-01",
                        "anthropic-beta" to "server-side-fallback-2026-07-01",
                        "content-type" to "application/json",
                    ),
                    body,
                    timeoutMs = 5 * 60_000,
                ))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                throw RecognizeError("network", e.toString())
            }
        }
        val text = res.text
        if (res.status == 401 || res.status == 403) throw RecognizeError("auth", text)
        if (res.status == 429 || res.status == 529) throw RecognizeError("rate", text)
        if (res.status != 200) throw RecognizeError("other", "HTTP ${res.status}")
        val msg = try { parseJson(text).obj } catch (_: Exception) { null } ?: throw RecognizeError("parse", "unexpected answer")
        if (msg["stop_reason"].string == "refusal") throw RecognizeError("refusal", msg["stop_details"].obj?.get("explanation").string ?: "refused")
        val out = msg["content"].arr?.mapNotNull { b -> b.obj?.takeIf { it["type"].string == "text" }?.get("text").string }?.joinToString("") ?: ""
        try {
            val items = parseJson(out).obj!!["items"].arr!!
            return items.map { Recognized.fromJson(it.obj!!) }.filter { it.title.isNotEmpty() }
        } catch (_: Exception) {
            throw RecognizeError("parse", if (msg["stop_reason"].string == "max_tokens") "too many items in one photo – try a closer photo" else "unexpected answer")
        }
    }
}
