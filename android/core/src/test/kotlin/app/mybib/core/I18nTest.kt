package app.mybib.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class I18nTest {
    private val strings = Strings.parse(File(System.getProperty("mybib.strings")).readText())
    private val de = strings.dicts.getValue("de")
    private val en = strings.dicts.getValue("en")

    @Test fun sameKeysAndPlaceholdersInBothLanguages() {
        assertEquals(de.keys, en.keys)
        val ph = Regex("""\{\w+\}""")
        for (k in de.keys) assertEquals(ph.findAll(de.getValue(k)).map { it.value }.toSet(), ph.findAll(en.getValue(k)).map { it.value }.toSet(), k)
    }

    @Test fun translatesWithFallbacks() {
        val s = Strings(mapOf("de" to mapOf("a" to "Hallo {name}"), "en" to mapOf("a" to "Hello {name}", "b" to "only en")))
        assertEquals("Hallo Eric", s.t("de", "a", mapOf("name" to "Eric")))
        assertEquals("only en", s.t("de", "b"))
        assertEquals("missing.key", s.t("de", "missing.key"))
    }

    @Test fun everyLiteralKeyUsedInTheCodeExists() {
        val root = File(System.getProperty("mybib.sources"))
        val src = listOf("app/src/main", "core/src/main").map { File(root, it) }.filter { it.exists() }
            .flatMap { d -> d.walk().filter { it.isFile && it.extension == "kt" }.toList() }
            .joinToString("\n") { it.readText() }
        val keys = Regex("""\bt\(\s*"([a-zA-Z0-9.\-]+)"""").findAll(src).map { it.groupValues[1] }.toSet()
        assertTrue(keys.size > 100, "found only ${keys.size} keys – is the app source there?")
        assertEquals(emptyList(), keys.filter { it !in de }.sorted())
    }

    @Test fun generatedKeysExist() {
        val gen = buildList {
            for (k in kinds) {
                addAll(listOf("kind.$k", "kind.$k.pl", "creator.$k"))
                for (s in statuses) add("status.$k.$s")
            }
            for (f in formats) add("format.$f")
            for (s in listOf("all", "wish", "lent", "recommend", "check")) add("scope.$s")
            for (s in sortKeys) add("sort.$s")
            for (s in listOf("cover", "publisher", "year", "isbn", "description")) add("bulk.field.$s")
            for (s in listOf("auth", "refusal", "rate", "network", "parse", "other")) add("ai.err.$s")
            for (m in listOf("own", "wish", "check")) add("scan.mode.$m")
            addAll(listOf("settings.googleHow1", "settings.googleHow2", "settings.googleHow3", "settings.googleHow4", "settings.model.claude-opus-5-5", "settings.model.claude-sonnet-5-5", "ai.conf.medium", "ai.conf.low"))
        }
        assertEquals(emptyList(), gen.filter { it !in de })
    }
}
