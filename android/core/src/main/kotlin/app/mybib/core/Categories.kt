package app.mybib.core

/** Default categories, grouped for the picker: id, German, English. */
class CategoryGroup(val de: String, val en: String, val items: List<List<String>>)

val defaultCategoryGroups = listOf(
    CategoryGroup("Kinder & Jugend", "Children & young adults", listOf(
        listOf("picture", "Bilderbuch", "Picture book"),
        listOf("children", "Kinderbuch", "Children's book"),
        listOf("youth", "Jugendbuch", "Young adult"),
        listOf("comic", "Comic & Graphic Novel", "Comics & graphic novels"),
    )),
    CategoryGroup("Belletristik", "Fiction", listOf(
        listOf("novel", "Roman & Erzählung", "Novels & stories"),
        listOf("crime", "Krimi & Thriller", "Crime & thriller"),
        listOf("fantasy", "Fantasy & Science-Fiction", "Fantasy & science fiction"),
        listOf("classic", "Klassiker, Drama & Lyrik", "Classics, drama & poetry"),
        listOf("humor", "Humor", "Humour"),
    )),
    CategoryGroup("Sachbuch", "Non-fiction", listOf(
        listOf("nonfiction", "Sachbuch", "Non-fiction"),
        listOf("guide", "Ratgeber", "Self-help & advice"),
        listOf("cooking", "Kochen & Trinken", "Food & drink"),
        listOf("travel", "Reise & Sprachführer", "Travel & phrasebooks"),
        listOf("hobby", "Sport, Outdoor & Hobby", "Sport, outdoors & hobbies"),
        listOf("arts", "Kunst, Musik & Design", "Art, music & design"),
        listOf("religion", "Religion & Philosophie", "Religion & philosophy"),
        listOf("reference", "Wörterbuch & Lernen", "Dictionaries & learning"),
    )),
)

private val byId: Map<String, List<String>> =
    defaultCategoryGroups.flatMap { g -> g.items.map { it[0] to listOf(it[1], it[2]) } }.toMap()

val defaultCategoryIds: List<String> = byId.keys.toList()

/** Display name: default categories are translated, own categories are shown as typed. */
fun categoryLabel(c: String, lang: String): String = byId[c]?.get(if (lang == "de") 0 else 1) ?: c

/** Accept an id, a German/English default name (any case) or an own category name. */
fun toCategory(v: String?): String? {
    val s = v?.trim()
    if (s.isNullOrEmpty()) return null
    if (s in byId) return s
    val low = s.lowercase()
    return byId.entries.firstOrNull { (_, n) -> n[0].lowercase() == low || n[1].lowercase() == low }?.key ?: s
}

/** Categories offered: the configured list (or the defaults) plus any used by items. */
fun allCategories(configured: List<String>, used: Iterable<String?>): List<String> {
    val list = (configured.ifEmpty { defaultCategoryIds }).toMutableList()
    for (c in used) if (c != null && c !in list) list += c
    return list
}
