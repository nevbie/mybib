package app.mybib.core

import kotlinx.serialization.json.JsonNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

fun item(vararg p: Pair<String, Any?>) = normalizeItem(draftOf("title" to "x") + draftOf(*p), now = "2026-01-01T00:00:00.000Z")

private fun ids(l: List<Item>) = l.map { it.id }

class IsbnTest {
    @Test fun validatesAndConverts() {
        assertTrue(isValidIsbn10("3446205799"))
        assertFalse(isValidIsbn10("344620579X"))
        assertEquals("9783446205796", isbn10to13("3446205799"))
        assertTrue(isValidEan13("9783446205796"))
        assertFalse(isValidEan13("9783446205797"))
    }

    @Test fun classifiesCodes() {
        assertEquals(Code("isbn", "9783446205796"), classifyCode("978-3-446-20579-6"))
        assertEquals(Code("isbn", "9783446205796"), classifyCode("3-446-20579-9"))
        assertEquals(Code("ean", "4006381333931"), classifyCode("4006381333931"))
        assertEquals(Code("ean", "724384260521"), classifyCode("724384260521"))
        assertNull(classifyCode("12345"))
    }
}

class NormalizeItemTest {
    @Test fun fillsDefaultsAndDropsJunk() {
        val i = normalizeItem("title" to " Open City ", "author" to "Teju Cole", "kind" to "spaceship", "rating" to 9, "foo" to 1)
        assertEquals("Open City", i.title)
        assertEquals(listOf("Teju Cole"), i.creators)
        assertEquals("book", i.kind)
        assertEquals(5, i.rating)
        assertTrue(i.owned)
        assertFalse(i.toJson().containsKey("foo"))
        assertFalse(i.toJson().values.contains(JsonNull))
    }

    @Test fun splitsCreatorStrings() {
        assertEquals(listOf("Mary Auld", "Elisa Paganelli"), item("creators" to "Mary Auld / Elisa Paganelli").creators)
        assertEquals(listOf("Abouet", "Sapin"), item("creators" to "Abouet & Sapin").creators)
    }

    @Test fun rejectsNonImageCoverData() {
        assertNull(item("coverData" to "javascript:alert(1)").coverData)
        assertEquals("data:image/jpeg;base64,AAA", item("coverData" to "data:image/jpeg;base64,AAA").coverData)
    }

    @Test fun turnsOldShelvesIntoRooms() {
        assertEquals("Foto 4", item("room" to "Foto-Import", "shelf" to "Foto 4").room)
        assertEquals("Regal 2", item("shelf" to "Regal 2").room)
        assertEquals("Wohnzimmer", item("room" to "Wohnzimmer", "shelf" to "oben").room)
    }

    @Test fun roundTripsThroughJsonAndCopyWithCanClear() {
        val i = item("id" to "a", "notes" to "n", "loans" to listOf(mapOf("to" to "Eric", "since" to "2026-01-02")))
        assertEquals(i.toJson(), normalizeItem(parseJson(i.toJson().toString()).obj!!).toJson())
        assertNull(i.copyWith("notes" to null).notes)
        assertEquals("Eric", i.openLoan?.to)
    }

    @Test fun keepsTheJsonKeyOrderOfTheWebApp() {
        val i = item("id" to "a", "year" to 2006, "needsCheck" to true)
        assertEquals(
            """{"id":"a","kind":"book","title":"x","creators":[],"year":2006,"tags":[],"format":"physical","owned":true,"status":"none","rating":0,"recommend":false,"loans":[],"needsCheck":true,"source":"manual","addedAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}""",
            i.toJson().toString(),
        )
    }
}

class SearchFilterSortTest {
    private val lib = listOf(
        item("id" to "a", "title" to "Der Koran", "creators" to listOf("Goodword"), "room" to "Wohnzimmer", "rating" to 4, "category" to "religion"),
        item("id" to "b", "title" to "Kalle Blomquist", "creators" to listOf("Astrid Lindgren"), "room" to "Kleines Zimmer", "status" to "done"),
        item("id" to "c", "title" to "Sind Dinos tot?", "creators" to listOf("Mai Thi Nguyen-Kim"), "owned" to false),
        item("id" to "d", "title" to "Ginseng Wurzeln", "creators" to listOf("Craig Thompson"), "room" to "Wohnzimmer", "loans" to listOf(mapOf("to" to "Eric", "since" to "2026-01-02"))),
        item("id" to "e", "title" to "Catan", "kind" to "game", "recommend" to true),
    )

    @Test fun foldsUmlautsAndCase() = assertEquals("grosse arger cafe", fold("Größe ÄRGER Café"))

    @Test fun searchesAcrossFields() {
        assertEquals(listOf("b"), ids(applyFilters(lib, Filters(q = "lindgren kalle"))))
        assertEquals(listOf("a", "d"), ids(applyFilters(lib, Filters(q = "wohnzimmer"))))
    }

    @Test fun filtersByScopeKindRoomCategoryRating() {
        assertEquals(listOf("c"), ids(applyFilters(lib, Filters(scope = "wish"))))
        assertEquals(listOf("d"), ids(applyFilters(lib, Filters(scope = "lent"))))
        assertEquals(listOf("e"), ids(applyFilters(lib, Filters(scope = "recommend"))))
        assertEquals(listOf("e"), ids(applyFilters(lib, Filters(kind = "game"))))
        assertEquals(listOf("c", "e"), ids(applyFilters(lib, Filters(room = ""))))
        assertEquals(listOf("a"), ids(applyFilters(lib, Filters(category = "religion"))))
        assertEquals(listOf("a"), ids(applyFilters(lib, Filters(minRating = 3))))
    }

    @Test fun ignoresArticlesWhenSortingByTitle() {
        assertEquals("koran", titleKey("Der Koran"))
        assertEquals(listOf("e", "d", "b", "a", "c"), ids(sortItems(lib, "title")))
    }

    @Test fun sortsBySurname() {
        assertEquals(listOf("e", "a", "b", "c", "d"), ids(sortItems(lib, "creator")))
        val hg = listOf(item("id" to "x", "title" to "B", "creators" to listOf("Laura Lamping (Hg.)")), item("id" to "y", "title" to "A", "creators" to listOf("Schami, Rafik")))
        assertEquals(listOf("x", "y"), ids(sortItems(hg, "creator")))
    }

    @Test fun naturalOrderForVolumes() {
        val v = listOf(item("id" to "10", "title" to "Band", "volume" to "10"), item("id" to "2", "title" to "Band", "volume" to "2"))
        assertEquals(listOf("2", "10"), ids(sortItems(v, "title")))
    }

    @Test fun summarisesRoomsOfOwnedPhysicalItems() {
        assertEquals(listOf("Kleines Zimmer" to 1, "Wohnzimmer" to 2, "" to 1), summarizePlaces(lib))
    }
}

class DuplicatesImportMergeTest {
    private val lib = listOf(
        item("id" to "a", "title" to "Open City", "creators" to listOf("Teju Cole"), "isbn" to "9783518466"),
        item("id" to "b", "title" to "Kafka am Strand", "creators" to listOf("Haruki Murakami")),
    )

    @Test fun findsDuplicates() {
        assertEquals("a", findDuplicate(lib, title = "anything", isbn = "9783518466")?.id)
        assertEquals("b", findDuplicate(lib, title = "kafka am strand!", creators = listOf("Haruki Murakami"))?.id)
        assertNull(findDuplicate(lib, title = "Kafka am Strand", creators = listOf("Someone Else")))
        val set = listOf(item("title" to "金瓶梅词话", "creators" to listOf("兰陵笑笑生"), "volume" to "1"))
        assertNull(findDuplicate(set, title = "金瓶梅词话", creators = listOf("兰陵笑笑生"), volume = "2"))
    }

    @Test fun roundTripsAnExport() {
        val back = parseImportFile(toExport(lib).toString()).items
        assertEquals(lib.map { it.toJson() }, back.map { it.toJson() })
    }

    @Test fun readsTheSkillFormatWithATopLevelRoom() {
        val r = parseImportFile(j(mapOf("room" to "Küche", "items" to listOf(mapOf("title" to "Käferkolonne"), mapOf("title" to "Freddy", "room" to "Wohnzimmer"), mapOf("nope" to 1)))).toString())
        assertEquals(listOf("Küche", "Wohnzimmer"), r.items.map { it.room })
        assertEquals("import", r.items.first().source)
        assertFalse(r.updateOnly)
    }

    @Test fun mergesNewerWinsDuplicatesCompletedUpdateOnlyAddsNothing() {
        val r = mergeItems(lib, listOf(
            lib[0].copyWith("notes" to "new", "updatedAt" to "2027-01-01T00:00:00.000Z"),
            item("title" to "Kafka am Strand", "creators" to listOf("Haruki Murakami"), "year" to 2006),
            item("title" to "Tremolo", "creators" to listOf("Tomi Ungerer")),
        ))
        assertEquals(listOf(1, 2, 0), listOf(r.added, r.updated, r.skipped))
        assertEquals(2006, r.items.first { it.id == "b" }.year)
        val u = parseImportFile(j(mapOf("updateOnly" to true, "items" to listOf(mapOf("title" to "Open City", "creators" to listOf("Teju Cole"), "category" to "Roman & Erzählung"), mapOf("title" to "New")))).toString())
        val r2 = mergeItems(lib, u.items, updateOnly = u.updateOnly)
        assertEquals(listOf(0, 1, 1), listOf(r2.added, r2.updated, r2.skipped))
        assertEquals("novel", r2.items.first().category)
    }

    @Test fun exportsCsvWithEscaping() {
        val csv = toCSV(listOf(item("title" to "Wurzeln; \"Ginseng\"", "creators" to listOf("A", "B"))))
        assertTrue(csv.split("\n")[1].contains("\"Wurzeln; \"\"Ginseng\"\"\""))
        assertTrue(csv.split("\n")[1].contains(";A, B;"))
        assertTrue(csv.startsWith("﻿kind;title;"))
    }
}

class CategoriesAndBulkTest {
    @Test fun mapsNamesToIds() {
        assertEquals(17, defaultCategoryIds.size)
        assertEquals("nonfiction", toCategory("Sachbuch"))
        assertEquals("picture", toCategory("picture book"))
        assertEquals("Gleitschirm", toCategory("Gleitschirm"))
        assertEquals("Young adult", categoryLabel("youth", "en"))
        assertEquals(listOf("novel", "youth"), allCategories(listOf("novel"), listOf("youth", null)))
    }

    @Test fun bulkTargets() {
        val full = item("title" to "A", "coverUrl" to "u", "publisher" to "p", "year" to 2000, "isbn" to "9780000000000", "description" to "d")
        val bare = item("title" to "B")
        val tried = item("title" to "C", "lookedUp" to "2026-10-01")
        assertTrue(missingInfo(full).isEmpty())
        assertEquals(listOf("B"), bulkTargets(listOf(full, bare, tried, item("title" to "D", "kind" to "game")), false).map { it.title })
        assertEquals(listOf("B", "C"), bulkTargets(listOf(full, bare, tried), true).map { it.title })
    }
}
