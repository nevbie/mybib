import XCTest
@testable import MybibCore

@MainActor
final class StoreTests: XCTestCase {
    func testSavesAndLoadsTheCatalogueAndSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mybib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = Store(dir: dir)
        a.load()
        let created = a.addItems([["title": "Open City", "room": "Wohnzimmer"], ["title": "Kafka am Strand", "category": "novel"]])
        XCTAssertEqual(created.count, 2)
        let x = created[0]
        a.updateItem(x.id, ["rating": 4])
        a.moveRoom("Wohnzimmer", "Küche")
        a.save()
        a.updateSettings(Settings(googleBooksKey: "g", lang: "en"))

        let b = Store(dir: dir)
        b.load()
        XCTAssertTrue(b.ready)
        XCTAssertEqual(b.items.count, 2)
        XCTAssertEqual(b.byId(x.id)?.rating, 4)
        XCTAssertEqual(b.byId(x.id)?.room, "Küche")
        XCTAssertEqual(b.settings.lang, "en")
        XCTAssertEqual(b.settings.googleBooksKey, "g")
        b.moveCategory("novel", "")
        XCTAssertTrue(b.items.allSatisfy { $0.category == nil })

        // the file has the shared format
        let raw = try decodeJSON(Data(contentsOf: dir.appendingPathComponent("items.json"))) as? JSONObject
        XCTAssertEqual(raw?["version"] as? Int, 1)
        XCTAssertEqual((raw?["items"] as? [Any])?.count, 2)
    }

    func testRoomsAndCategories() {
        let s = Store(dir: FileManager.default.temporaryDirectory.appendingPathComponent("mybib-\(UUID().uuidString)"))
        s.addItems([["title": "A", "room": "Keller", "category": "Gleitschirm"]])
        XCTAssertEqual(s.rooms(lang: "de"), ["Küche", "Wohnzimmer", "Kleines Zimmer", "Keller"])
        XCTAssertEqual(s.rooms(lang: "en").first, "Kitchen")
        XCTAssertEqual(s.categories().last, "Gleitschirm")
        XCTAssertEqual(s.categories().count, 18)
    }
}
