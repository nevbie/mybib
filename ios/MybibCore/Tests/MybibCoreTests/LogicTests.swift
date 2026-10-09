import XCTest
@testable import MybibCore

final class IsbnTests: XCTestCase {
    func testValidatesAndConverts() {
        XCTAssertTrue(isValidIsbn10("3446205799"))
        XCTAssertFalse(isValidIsbn10("344620579X"))
        XCTAssertEqual(isbn10to13("3446205799"), "9783446205796")
        XCTAssertTrue(isValidEan13("9783446205796"))
        XCTAssertFalse(isValidEan13("9783446205797"))
    }

    func testClassifiesCodes() {
        XCTAssertEqual(classifyCode("978-3-446-20579-6"), ScannedCode(type: "isbn", code: "9783446205796"))
        XCTAssertEqual(classifyCode("3-446-20579-9"), ScannedCode(type: "isbn", code: "9783446205796"))
        XCTAssertEqual(classifyCode("4006381333931"), ScannedCode(type: "ean", code: "4006381333931"))
        XCTAssertEqual(classifyCode("724384260521"), ScannedCode(type: "ean", code: "724384260521"))
        XCTAssertNil(classifyCode("12345"))
    }
}

final class NormalizeTests: XCTestCase {
    func testFillsDefaultsAndDropsJunk() {
        let i = normalizeItem(["title": " Open City ", "author": "Teju Cole", "kind": "spaceship", "rating": 9, "foo": 1])
        XCTAssertEqual(i.title, "Open City")
        XCTAssertEqual(i.creators, ["Teju Cole"])
        XCTAssertEqual(i.kind, "book")
        XCTAssertEqual(i.rating, 5)
        XCTAssertTrue(i.owned)
        XCTAssertNil(i.toJSON()["foo"])
        XCTAssertFalse(i.toJSON().values.contains { $0 is NSNull })
    }

    func testSplitsCreatorStrings() {
        XCTAssertEqual(item(["creators": "Mary Auld / Elisa Paganelli"]).creators, ["Mary Auld", "Elisa Paganelli"])
        XCTAssertEqual(item(["creators": "Abouet & Sapin"]).creators, ["Abouet", "Sapin"])
    }

    func testRejectsNonImageCoverData() {
        XCTAssertNil(item(["coverData": "javascript:alert(1)"]).coverData)
        XCTAssertEqual(item(["coverData": "data:image/jpeg;base64,AAA"]).coverData, "data:image/jpeg;base64,AAA")
    }

    func testTurnsOldShelvesIntoRooms() {
        XCTAssertEqual(item(["room": "Foto-Import", "shelf": "Foto 4"]).room, "Foto 4")
        XCTAssertEqual(item(["shelf": "Regal 2"]).room, "Regal 2")
        XCTAssertEqual(item(["room": "Wohnzimmer", "shelf": "oben"]).room, "Wohnzimmer")
    }

    func testRoundTripsThroughJSONAndCopyWithCanClear() throws {
        let loans: [JSONObject] = [["to": "Eric", "since": "2026-01-02"]]
        let i = item(["id": "a", "notes": "n", "loans": loans])
        let back = try decodeJSON(encodeJSON(i.toJSON())) as? JSONObject ?? [:]
        assertJSON(normalizeItem(back).toJSON(), i.toJSON())
        XCTAssertEqual(normalizeItem(back), i)
        XCTAssertNil(i.copyWith(["notes": NSNull()]).notes)
        XCTAssertEqual(i.openLoan?.to, "Eric")
    }

    func testLooseTypes() {
        let i = item(["year": "2006", "pages": 120.4, "owned": 0, "recommend": 1, "volume": 3, "tags": "a; b"])
        XCTAssertEqual(i.year, 2006)
        XCTAssertEqual(i.pages, 120)
        XCTAssertTrue(i.owned)
        XCTAssertFalse(i.recommend)
        XCTAssertEqual(i.volume, "3")
        XCTAssertEqual(i.tags, ["a", "b"])
        XCTAssertNil(i.toJSON()["needsCheck"])
    }
}

final class SearchSortTests: XCTestCase {
    let lib: [Item] = [
        item(["id": "a", "title": "Der Koran", "creators": ["Goodword"], "room": "Wohnzimmer", "rating": 4, "category": "religion"]),
        item(["id": "b", "title": "Kalle Blomquist", "creators": ["Astrid Lindgren"], "room": "Kleines Zimmer", "status": "done"]),
        item(["id": "c", "title": "Sind Dinos tot?", "creators": ["Mai Thi Nguyen-Kim"], "owned": false]),
        item(["id": "d", "title": "Ginseng Wurzeln", "creators": ["Craig Thompson"], "room": "Wohnzimmer",
              "loans": [["to": "Eric", "since": "2026-01-02"] as JSONObject]]),
        item(["id": "e", "title": "Catan", "kind": "game", "recommend": true]),
    ]

    func testFoldsUmlautsAndCase() {
        XCTAssertEqual(fold("Größe ÄRGER Café"), "grosse arger cafe")
    }

    func testSearchesAcrossFields() {
        XCTAssertEqual(ids(applyFilters(lib, Filters(q: "lindgren kalle"))), ["b"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(q: "wohnzimmer"))), ["a", "d"])
    }

    func testFiltersByScopeKindRoomCategoryRating() {
        XCTAssertEqual(ids(applyFilters(lib, Filters(scope: "wish"))), ["c"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(scope: "lent"))), ["d"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(scope: "recommend"))), ["e"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(kind: "game"))), ["e"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(room: ""))), ["c", "e"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(category: "religion"))), ["a"])
        XCTAssertEqual(ids(applyFilters(lib, Filters(minRating: 3))), ["a"])
    }

    func testIgnoresArticlesWhenSortingByTitle() {
        XCTAssertEqual(titleKey("Der Koran"), "koran")
        XCTAssertEqual(ids(sortItems(lib, "title")), ["e", "d", "b", "a", "c"])
    }

    func testSortsBySurname() {
        XCTAssertEqual(ids(sortItems(lib, "creator")), ["e", "a", "b", "c", "d"])
        let hg = [item(["id": "x", "title": "B", "creators": ["Laura Lamping (Hg.)"]]), item(["id": "y", "title": "A", "creators": ["Schami, Rafik"]])]
        XCTAssertEqual(ids(sortItems(hg, "creator")), ["x", "y"])
    }

    func testNaturalOrderForVolumes() {
        let v = [item(["id": "10", "title": "Band", "volume": "10"]), item(["id": "2", "title": "Band", "volume": "2"])]
        XCTAssertEqual(ids(sortItems(v, "title")), ["2", "10"])
    }

    func testSortsByPlaceWithoutRoomLast() {
        XCTAssertEqual(ids(sortItems(lib, "place")), ["b", "d", "a", "e", "c"])
    }

    func testSummarisesRoomsOfOwnedPhysicalItems() {
        let s = summarizePlaces(lib).map { "\($0.room)=\($0.count)" }
        XCTAssertEqual(s, ["Kleines Zimmer=1", "Wohnzimmer=2", "=1"])
    }

    func testKnownPeople() {
        let l = [
            item(["loans": [["to": "Eric", "since": "2026-01-02"], ["to": "Anna", "since": "2026-03-01", "returned": "2026-03-05"]] as [JSONObject]]),
            item(["loans": [["to": "Eric", "since": "2026-05-01"]] as [JSONObject]]),
        ]
        XCTAssertEqual(knownPeople(l), ["Eric", "Anna"])
    }
}

final class ImportMergeTests: XCTestCase {
    let lib: [Item] = [
        item(["id": "a", "title": "Open City", "creators": ["Teju Cole"], "isbn": "9783518466"]),
        item(["id": "b", "title": "Kafka am Strand", "creators": ["Haruki Murakami"]]),
    ]

    func testFindsDuplicates() {
        XCTAssertEqual(findDuplicate(lib, title: "anything", isbn: "9783518466")?.id, "a")
        XCTAssertEqual(findDuplicate(lib, title: "kafka am strand!", creators: ["Haruki Murakami"])?.id, "b")
        XCTAssertNil(findDuplicate(lib, title: "Kafka am Strand", creators: ["Someone Else"]))
        let set = [item(["title": "金瓶梅词话", "creators": ["兰陵笑笑生"], "volume": "1"])]
        XCTAssertNil(findDuplicate(set, title: "金瓶梅词话", creators: ["兰陵笑笑生"], volume: "2"))
    }

    func testRoundTripsAnExport() throws {
        let text = String(decoding: try encodeJSON(toExport(lib)), as: UTF8.self)
        let back = try parseImportFile(text).items
        XCTAssertEqual(back, lib)
        assertJSON(back.map { $0.toJSON() }, lib.map { $0.toJSON() })
    }

    func testReadsTheSkillFormatWithATopLevelRoom() throws {
        let file: JSONObject = ["room": "Küche", "items": [["title": "Käferkolonne"], ["title": "Freddy", "room": "Wohnzimmer"], ["nope": 1]] as [JSONObject]]
        let r = try parseImportFile(String(decoding: try encodeJSON(file), as: UTF8.self))
        XCTAssertEqual(r.items.map(\.room), ["Küche", "Wohnzimmer"])
        XCTAssertEqual(r.items.first?.source, "import")
        XCTAssertFalse(r.updateOnly)
    }

    func testRejectsFilesWithoutItems() {
        XCTAssertThrowsError(try parseImportFile("{\"items\": []}"))
        XCTAssertThrowsError(try parseImportFile("not json"))
    }

    func testMergesNewerWinsDuplicatesCompletedUpdateOnlyAddsNothing() throws {
        let r = mergeItems(lib, [
            lib[0].copyWith(["notes": "new", "updatedAt": "2027-01-01T00:00:00.000Z"]),
            item(["title": "Kafka am Strand", "creators": ["Haruki Murakami"], "year": 2006]),
            item(["title": "Tremolo", "creators": ["Tomi Ungerer"]]),
        ])
        XCTAssertEqual([r.added, r.updated, r.skipped], [1, 2, 0])
        XCTAssertEqual(r.items.first { $0.id == "b" }?.year, 2006)
        let file: JSONObject = ["updateOnly": true, "items": [
            ["title": "Open City", "creators": ["Teju Cole"], "category": "Roman & Erzählung"] as JSONObject,
            ["title": "New"] as JSONObject,
        ]]
        let u = try parseImportFile(String(decoding: try encodeJSON(file), as: UTF8.self))
        let r2 = mergeItems(lib, u.items, updateOnly: u.updateOnly)
        XCTAssertEqual([r2.added, r2.updated, r2.skipped], [0, 1, 1])
        XCTAssertEqual(r2.items.first?.category, "novel")
    }

    func testExportsCSVWithEscaping() {
        let csv = toCSV([item(["title": "Wurzeln; \"Ginseng\"", "creators": ["A", "B"]])])
        let line = csv.components(separatedBy: "\n")[1]
        XCTAssertTrue(line.contains("\"Wurzeln; \"\"Ginseng\"\"\""))
        XCTAssertTrue(line.contains(";A, B;"))
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}kind;title;"))
        XCTAssertTrue(line.contains(";physical;true;none;0;false;"))
    }
}

final class CategoryBulkTests: XCTestCase {
    func testMapsNamesToIds() {
        XCTAssertEqual(defaultCategoryIds.count, 17)
        XCTAssertEqual(toCategory("Sachbuch"), "nonfiction")
        XCTAssertEqual(toCategory("picture book"), "picture")
        XCTAssertEqual(toCategory("Gleitschirm"), "Gleitschirm")
        XCTAssertEqual(categoryLabel("youth", "en"), "Young adult")
        XCTAssertEqual(allCategories(["novel"], ["youth", nil]), ["novel", "youth"])
    }

    func testBulkTargets() {
        let full = item(["title": "A", "coverUrl": "u", "publisher": "p", "year": 2000, "isbn": "9780000000000", "description": "d"])
        let bare = item(["title": "B"])
        let tried = item(["title": "C", "lookedUp": "2026-10-01"])
        XCTAssertTrue(missingInfo(full).isEmpty)
        XCTAssertEqual(bulkTargets([full, bare, tried, item(["title": "D", "kind": "game"])], false).map(\.title), ["B"])
        XCTAssertEqual(bulkTargets([full, bare, tried], true).map(\.title), ["B", "C"])
    }
}
