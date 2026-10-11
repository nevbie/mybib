package app.mybib.core

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StoreTest {
    @Test fun savesAndLoadsTheCatalogueAndSettings() {
        val dir = Files.createTempDirectory("mybib").toFile()
        val a = Store(dir)
        a.load()
        val (x, _) = a.addItems(listOf(draftOf("title" to "Open City", "room" to "Wohnzimmer"), draftOf("title" to "Kafka am Strand", "category" to "novel")))
        a.updateItem(x.id, "rating" to 4)
        a.moveRoom("Wohnzimmer", "Küche")
        a.updateSettings(Settings(lang = "en", googleBooksKey = "g"))
        a.flush()

        val text = dir.resolve("items.json").readText()
        assertTrue(text.startsWith("""{"version":1,"items":[{"id":"""))

        val b = Store(dir)
        b.load()
        assertEquals(2, b.items.value.size)
        assertEquals(4, b.byId(x.id)?.rating)
        assertEquals("Küche", b.byId(x.id)?.room)
        assertEquals("en", b.settings.value.lang)
        assertEquals("g", b.settings.value.googleBooksKey)
        b.moveCategory("novel", "")
        assertTrue(b.items.value.none { it.category != null })
        dir.deleteRecursively()
    }
}
