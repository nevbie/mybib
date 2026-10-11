import XCTest
@testable import MybibCore

private func vol(_ title: String, _ authors: [String]) -> JSONObject {
    let info: JSONObject = [
        "title": title,
        "authors": authors,
        "publisher": "Suhrkamp",
        "publishedDate": "2012-03-01",
        "industryIdentifiers": [["type": "ISBN_13", "identifier": "9783518464547"]],
        "imageLinks": ["thumbnail": "http://books.google.com/x&edge=curl"],
    ]
    return ["volumeInfo": info]
}

/// Google answers with `google`, everything else (Open Library) with no results.
private func lookup(google: @escaping () -> (Int, Any)) -> Lookup {
    Lookup(http: MockHTTP { req in
        let empty: JSONObject = ["docs": [Any]()]
        return (req.url?.host ?? "").contains("googleapis") ? google() : (200, empty)
    })
}

final class LookupTests: XCTestCase {
    func testTakesAClearTitleAndAuthorMatch() async {
        let l = lookup { (200, ["items": [vol("Something else", ["X"]), vol("Open City", ["Teju Cole"])]] as JSONObject) }
        let c = await l.findBestMatch(item(["title": "Open City", "creators": ["Teju Cole"]]))
        XCTAssertEqual(c?.data["publisher"] as? String, "Suhrkamp")
        XCTAssertEqual(c?.coverUrl, "https://books.google.com/x")
        XCTAssertEqual(c?.data["isbn"] as? String, "9783518464547")
        XCTAssertEqual(c?.data["year"] as? Int, 2012)
    }

    func testRejectsADifferentAuthorAndLooseTitlesWithoutAuthor() async {
        let a = lookup { (200, ["items": [vol("Open City", ["Someone Else"])]] as JSONObject) }
        let c1 = await a.findBestMatch(item(["title": "Open City", "creators": ["Teju Cole"]]))
        XCTAssertNil(c1)
        let b = lookup { (200, ["items": [vol("Sahara Reiseführer Marokko", ["A"])]] as JSONObject) }
        let c2 = await b.findBestMatch(item(["title": "Sahara Marokko"]))
        XCTAssertNil(c2)
    }

    func testReportsTheGoogleQuota() async {
        let l = lookup { (429, JSONObject()) }
        _ = l.takeGoogleProblem()
        let c = await l.findBestMatch(item(["title": "Open City", "creators": ["Teju Cole"]]))
        XCTAssertNil(c)
        XCTAssertEqual(l.takeGoogleProblem(), "quota")
        XCTAssertEqual(l.takeGoogleProblem(), "")
    }

    func testEnrichPatchFillsOnlyEmptyFields() {
        let c = Candidate(["title": "Open City", "creators": ["Teju Cole"], "publisher": "Suhrkamp", "year": 2012, "coverUrl": "c"], "g")
        let patch = enrichPatch(["title": "Open City", "creators": ["Teju Cole"], "publisher": "Mein Verlag"], c)
        assertJSON(patch, ["year": 2012, "coverUrl": "c"] as JSONObject)
    }

    func testMatchScoreAndTitleOverlap() {
        let c = Candidate(["title": "Open City", "creators": ["Teju Cole"]], "g")
        XCTAssertEqual(matchScore("Open City", ["Teju Cole"], c), 1, accuracy: 0.001)
        XCTAssertEqual(matchScore("Open City", ["Someone Else"], c), 0.7, accuracy: 0.001)
        XCTAssertEqual(titleOverlap("Sahara Marokko", "Sahara Reiseführer Marokko"), 2.0 / 3.0, accuracy: 0.001)
    }

    func testClaudePhotoRecognitionParsesStructuredOutputAndErrors() async throws {
        let answer: JSONObject = ["items": [[
            "kind": "book", "title": " 金瓶梅词话 ", "creators": ["兰陵笑笑生"], "series": "", "volume": "3", "publisher": "",
            "language": "zh", "confidence": "medium", "remark": "blurry",
        ] as JSONObject]]
        let answerText = String(decoding: try encodeJSON(answer), as: UTF8.self)
        let ok = MockHTTP { _ in
            (200, ["stop_reason": "end_turn", "content": [["type": "text", "text": answerText]]] as JSONObject)
        }
        let r = try await Claude(http: ok).recognizePhoto(apiKey: "k", model: "claude-opus-5-5", jpeg: Data([1, 2, 3]))
        let sent = ok.requests.last
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try decodeJSON(sent?.httpBody ?? Data()) as? JSONObject
        XCTAssertEqual(body?["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body?["fallbacks"] as? String, "default")
        let config = body?["output_config"] as? JSONObject
        XCTAssertEqual(config?["effort"] as? String, "medium")
        XCTAssertEqual((config?["format"] as? JSONObject)?["type"] as? String, "json_schema")
        XCTAssertEqual(r.count, 1)
        let expected: JSONObject = ["kind": "book", "title": "金瓶梅词话", "creators": ["兰陵笑笑生"], "volume": "3", "language": "zh", "needsCheck": true, "source": "ai"]
        assertJSON(r.first?.toDraft(), expected)

        let bad = MockHTTP { _ in (401, ["error": JSONObject()] as JSONObject) }
        do {
            _ = try await Claude(http: bad).recognizePhoto(apiKey: "bad", model: "m", jpeg: Data([1]))
            XCTFail("expected an error")
        } catch let e as RecognizeError {
            XCTAssertEqual(e.code, "auth")
        }
    }
}
