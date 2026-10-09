package app.mybib.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Item drafts, patches and online results are loose JSON maps, as in the web app.
 * A key mapped to [JsonNull] in a patch removes that optional value.
 */
typealias Draft = Map<String, JsonElement>

/** Turn plain Kotlin values (strings, numbers, lists, maps, loans …) into JSON. */
fun j(v: Any?): JsonElement = when (v) {
    null -> JsonNull
    is JsonElement -> v
    is String -> JsonPrimitive(v)
    is Number -> JsonPrimitive(v)
    is Boolean -> JsonPrimitive(v)
    is Loan -> v.toJson()
    is Map<*, *> -> JsonObject(v.entries.associate { (k, x) -> k.toString() to j(x) })
    is Iterable<*> -> JsonArray(v.map(::j))
    is Array<*> -> JsonArray(v.map(::j))
    else -> JsonPrimitive(v.toString())
}

/** Draft from pairs; null values stay as [JsonNull] (= "clear this field" in a patch). */
fun draftOf(vararg pairs: Pair<String, Any?>): Draft = linkedMapOf(*pairs.map { (k, v) -> k to j(v) }.toTypedArray())

/** JSON object without the null values (like Dart's `..removeWhere((k, v) => v == null)`). */
fun objOf(vararg pairs: Pair<String, Any?>): JsonObject =
    JsonObject(pairs.filter { it.second != null && it.second !is JsonNull }.associate { (k, v) -> k to j(v) })

val JsonElement?.isNull get() = this == null || this is JsonNull

private val JsonPrimitive.isBool get() = !isString && (content == "true" || content == "false")

/** The string value, or null for anything that is not a JSON string. */
val JsonElement?.string: String? get() = if (this is JsonPrimitive && isString) content else null

/** The number as text, or null for anything that is not a JSON number. */
val JsonElement?.numberText: String? get() = if (this is JsonPrimitive && this !is JsonNull && !isString && !isBool) content else null

val JsonElement?.isTrue get() = this is JsonPrimitive && !isString && content == "true"
val JsonElement?.isFalse get() = this is JsonPrimitive && !isString && content == "false"

val JsonElement?.obj: JsonObject? get() = this as? JsonObject
val JsonElement?.arr: JsonArray? get() = this as? JsonArray

/** A JSON whole number (or a string of one, as Dart's `int.tryParse`). */
val JsonElement?.int: Int? get() = numberText?.toIntOrNull()

/** Strings in a JSON array (non-strings dropped). */
val JsonElement?.strings: List<String> get() = arr?.mapNotNull { it.string } ?: emptyList()

/** Empty for lookup purposes: missing, null, "" or []. */
fun JsonElement?.isEmptyValue() = isNull || string == "" || (this is JsonArray && isEmpty())

val json = Json { ignoreUnknownKeys = true }

fun parseJson(text: String): JsonElement = json.parseToJsonElement(text)

fun JsonObject.merge(patch: Draft): JsonObject = JsonObject(this + patch)
