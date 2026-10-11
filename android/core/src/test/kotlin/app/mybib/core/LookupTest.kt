package app.mybib.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

private fun vol(title: String, authors: List<String>) = mapOf(
    "volumeInfo" to mapOf(
        "title" to title,
        "authors" to authors,
        "publisher" to "Suhrkamp",
        "publishedDate" to "2012-03-01",
        "industryIdentifiers" to listOf(mapOf("type" to "ISBN_13", "identifier" to "9783518464547")),
        "imageLinks" to mapOf("thumbnail" to "http://books.google.com/x&edge=curl"),
    ),
)

private fun json(o: Any?, status: Int = 200) = HttpResponse(status, mapOf("content-type" to "application/json"), j(o).toString().encodeToByteArray())

/** Lookup against fake services; every HEAD (cover probe) finds an image. */
private fun mock(handler: (HttpRequest) -> HttpResponse) = Lookup { req ->
    if (req.method == "HEAD") HttpResponse(200, mapOf("content-type" to "image/jpeg", "content-length" to "5000")) else handler(req)
}

private val HttpRequest.host get() = java.net.URI(url).host

class LookupTest {
    @Test fun takesAClearTitleAndAuthorMatch() = runBlocking {
        val l = mock { if (it.host.contains("googleapis")) json(mapOf("items" to listOf(vol("Something else", listOf("X")), vol("Open City", listOf("Teju Cole"))))) else json(mapOf("docs" to emptyList<Any>())) }
        val c = l.findBestMatch(item("title" to "Open City", "creators" to listOf("Teju Cole")))
        assertEquals("Suhrkamp", c?.data?.get("publisher").string)
        assertEquals("https://books.google.com/x", c?.coverUrl)
    }

    @Test fun rejectsADifferentAuthorAndLooseTitlesWithoutAuthor() = runBlocking {
        val a = mock { if (it.host.contains("googleapis")) json(mapOf("items" to listOf(vol("Open City", listOf("Someone Else"))))) else json(mapOf("docs" to emptyList<Any>())) }
        assertNull(a.findBestMatch(item("title" to "Open City", "creators" to listOf("Teju Cole"))))
        val b = mock { if (it.host.contains("googleapis")) json(mapOf("items" to listOf(vol("Sahara Reiseführer Marokko", listOf("A"))))) else json(mapOf("docs" to emptyList<Any>())) }
        assertNull(b.findBestMatch(item("title" to "Sahara Marokko")))
    }

    @Test fun reportsTheGoogleQuota() = runBlocking {
        val l = mock { if (it.host.contains("googleapis")) json(emptyMap<String, Any>(), 429) else json(mapOf("docs" to emptyList<Any>())) }
        l.takeGoogleProblem()
        assertNull(l.findBestMatch(item("title" to "Open City", "creators" to listOf("Teju Cole"))))
        assertEquals("quota", l.takeGoogleProblem())
        assertEquals("", l.takeGoogleProblem())
    }

    @Test fun mergesIsbnResultsAndPrefersOpenLibraryCovers() = runBlocking {
        val l = mock {
            if (it.host.contains("googleapis")) json(mapOf("items" to listOf(vol("Open City", listOf("Teju Cole")))))
            else json(mapOf("ISBN:9783518464547" to mapOf("title" to "Open City", "number_of_pages" to 330, "cover" to mapOf("medium" to "https://covers.openlibrary.org/b/id/1-M.jpg"))))
        }
        val c = l.lookupIsbn("9783518464547")!!
        assertEquals("Google Books + Open Library", c.via)
        assertEquals("https://covers.openlibrary.org/b/id/1-M.jpg", c.coverUrl)
        assertEquals(330, c.data["pages"].int)
        assertEquals("9783518464547", c.data["isbn"].string)
    }

    @Test fun enrichPatchFillsOnlyEmptyFields() {
        val c = Candidate(objOf("title" to "Open City", "creators" to listOf("Teju Cole"), "publisher" to "Suhrkamp", "year" to 2012, "coverUrl" to "c"), "g")
        assertEquals(draftOf("year" to 2012, "coverUrl" to "c"), enrichPatch(draftOf("title" to "Open City", "creators" to listOf("Teju Cole"), "publisher" to "Mein Verlag"), c))
    }

    @Test fun claudePhotoRecognitionParsesStructuredOutputAndErrors() = runBlocking {
        var sent: HttpRequest? = null
        val claude = Claude { req ->
            sent = req
            json(mapOf(
                "stop_reason" to "end_turn",
                "content" to listOf(mapOf("type" to "text", "text" to j(mapOf("items" to listOf(mapOf(
                    "kind" to "book", "title" to " 金瓶梅词话 ", "creators" to listOf("兰陵笑笑生"), "series" to "", "volume" to "3",
                    "publisher" to "", "language" to "zh", "confidence" to "medium", "remark" to "blurry",
                )))).toString())),
            ))
        }
        val r = claude.recognizePhoto(apiKey = "k", model = "claude-opus-5-5", jpeg = byteArrayOf(1, 2, 3))
        val req = sent!!
        assertEquals("k", req.headers["x-api-key"])
        assertEquals("server-side-fallback-2026-07-01", req.headers["anthropic-beta"])
        assertEquals("2023-06-01", req.headers["anthropic-version"])
        val body = parseJson(req.body!!.decodeToString()).obj!!
        assertEquals("claude-opus-5-5", body["model"].string)
        assertEquals("default", body["fallbacks"].string)
        assertEquals(16000, body["max_tokens"].int)
        assertEquals("medium", body["output_config"].obj!!["effort"].string)
        assertEquals("json_schema", body["output_config"].obj!!["format"].obj!!["type"].string)
        assertEquals("AQID", body["messages"].arr!![0].obj!!["content"].arr!![0].obj!!["source"].obj!!["data"].string)
        assertEquals(
            draftOf("kind" to "book", "title" to "金瓶梅词话", "creators" to listOf("兰陵笑笑生"), "volume" to "3", "language" to "zh", "needsCheck" to true, "source" to "ai"),
            r.single().toDraft(),
        )
        val bad = Claude { json(mapOf("error" to emptyMap<String, Any>()), 401) }
        val e = assertFailsWith<RecognizeError> { bad.recognizePhoto(apiKey = "bad", model = "m", jpeg = byteArrayOf(1)) }
        assertEquals("auth", e.code)
    }
}
