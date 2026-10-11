import XCTest
@testable import MybibCore

final class I18nTests: XCTestCase {
    let strings: Strings = Strings.load(repoRoot.appendingPathComponent("shared/strings.json"))
    var de: [String: String] { strings.table["de"] ?? [:] }
    var en: [String: String] { strings.table["en"] ?? [:] }

    private func placeholders(_ s: String) -> Set<String> {
        let re = Rx(#"\{\w+\}"#)
        var out = Set<String>()
        var rest = s
        while let m = re.first(rest), let r = rest.range(of: m) {
            out.insert(m)
            rest = String(rest[r.upperBound...])
        }
        return out
    }

    func testLoadsSharedFile() {
        XCTAssertGreaterThan(de.count, 200)
    }

    func testSameKeysAndPlaceholdersInBothLanguages() {
        XCTAssertEqual(Set(en.keys), Set(de.keys))
        for (k, v) in de {
            XCTAssertEqual(placeholders(en[k] ?? ""), placeholders(v), k)
        }
    }

    func testTranslatesWithFallbacks() {
        XCTAssertEqual(strings.t("de", "scan.added", ["n": 3]), "3 hinzugefügt")
        XCTAssertEqual(strings.t("fr", "scan.added", ["n": 3]), "3 added")
        XCTAssertEqual(strings.t("de", "no.such.key"), "no.such.key")
    }

    /// Every literal key used in the app code (`t("key"` …) exists.
    func testEveryLiteralKeyUsedInTheAppExists() throws {
        let appDir = repoRoot.appendingPathComponent("ios/Mybib")
        guard let files = FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil) else {
            return XCTFail("no app sources at \(appDir.path)")
        }
        var src = ""
        for case let f as URL in files where f.pathExtension == "swift" {
            src += try String(contentsOf: f, encoding: .utf8) + "\n"
        }
        XCTAssertFalse(src.isEmpty)
        let re = try NSRegularExpression(pattern: #"\bt\(\s*"([a-zA-Z0-9.\-]+)""#)
        let matches = re.matches(in: src, options: [], range: NSRange(src.startIndex..., in: src))
        let keys = Set(matches.compactMap { m in Range(m.range(at: 1), in: src).map { String(src[$0]) } })
        XCTAssertGreaterThan(keys.count, 100)
        XCTAssertEqual(keys.filter { de[$0] == nil }.sorted(), [])
    }

    func testGeneratedKeysExist() {
        var gen: [String] = []
        for k in kinds {
            gen += ["kind.\(k)", "kind.\(k).pl", "creator.\(k)"] + statuses.map { "status.\(k).\($0)" }
        }
        gen += formats.map { "format.\($0)" }
        gen += ["all", "wish", "lent", "recommend", "check"].map { "scope.\($0)" }
        gen += sortKeys.map { "sort.\($0)" }
        gen += ["cover", "publisher", "year", "isbn", "description"].map { "bulk.field.\($0)" }
        gen += ["auth", "refusal", "rate", "network", "parse", "other"].map { "ai.err.\($0)" }
        gen += ["own", "wish", "check"].map { "scan.mode.\($0)" }
        gen += ["settings.googleHow1", "settings.googleHow4", "settings.model.claude-opus-5-5", "settings.model.claude-sonnet-5-5", "ai.conf.medium", "ai.conf.low"]
        XCTAssertEqual(gen.filter { de[$0] == nil }, [])
    }
}
