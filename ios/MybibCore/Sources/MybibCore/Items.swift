import Foundation

private let accents: [String: Character] = [
    "àáâãäåāăą": "a", "çćĉċč": "c", "ďđ": "d", "èéêëēĕėęě": "e", "ĝğġģ": "g", "ĥħ": "h", "ìíîïĩīĭįı": "i", "ĵ": "j", "ķ": "k",
    "ĺļľŀł": "l", "ñńņňŉ": "n", "òóôõöøōŏő": "o", "ŕŗř": "r", "śŝşšș": "s", "ţťŧț": "t", "ùúûüũūŭůűų": "u", "ŵ": "w", "ýÿŷ": "y", "źżž": "z",
]
private let accentMap: [Character: Character] = {
    var m: [Character: Character] = [:]
    for (chars, base) in accents {
        for ch in chars { m[ch] = base }
    }
    return m
}()

/// Lower-case, strip accents and punctuation – for search and duplicate detection.
public func fold(_ s: String) -> String {
    let low = s.lowercased()
        .replacingOccurrences(of: "ß", with: "ss")
        .replacingOccurrences(of: "æ", with: "ae")
        .replacingOccurrences(of: "œ", with: "oe")
    var out = ""
    out.reserveCapacity(low.utf8.count)
    for ch in low { out.append(accentMap[ch] ?? ch) }
    return Rx.nonWord.replace(out, " ").trimmingCharacters(in: .whitespaces)
}

/// Probable duplicate: same ISBN, or same title + first creator (or both unknown) + volume.
public func findDuplicate(_ items: [Item], title: String, isbn: String? = nil, creators: [String] = [], volume: String? = nil,
                          kind: String? = nil, format: String? = nil) -> Item? {
    if let isbn, !isbn.isEmpty, let hit = items.first(where: { $0.isbn == isbn }) { return hit }
    let t = fold(title)
    if t.isEmpty { return nil }
    let c = creators.first.map(fold) ?? ""
    let v = volume.map(fold) ?? ""
    return items.first { i in
        fold(i.title) == t
            && (i.creators.first.map(fold) ?? "") == c
            && (i.volume.map(fold) ?? "") == v
            && (kind == nil || i.kind == kind)
            && (format == nil || i.format == format)
    }
}

public func findDuplicateOf(_ items: [Item], _ d: Item) -> Item? {
    findDuplicate(items, title: d.title, isbn: d.isbn, creators: d.creators, volume: d.volume, kind: d.kind, format: d.format)
}

public struct Filters: Equatable, Sendable {
    public var q: String
    /// "all" or a kind
    public var kind: String
    public var status: String
    /// all / owned / wish / lent / recommend / check
    public var scope: String
    public var format: String
    /// "all", "" = no room, or a room
    public var room: String
    /// "all", "" = no category, or a category
    public var category: String
    public var minRating: Int

    public init(q: String = "", kind: String = "all", status: String = "all", scope: String = "all", format: String = "all",
                room: String = "all", category: String = "all", minRating: Int = 0) {
        self.q = q
        self.kind = kind
        self.status = status
        self.scope = scope
        self.format = format
        self.room = room
        self.category = category
        self.minRating = minRating
    }

    public var extraActive: Int {
        [status != "all", format != "all", room != "all", category != "all", minRating > 0].filter { $0 }.count
    }
}

public func searchText(_ i: Item) -> String {
    var parts: [String] = [i.title]
    if let s = i.subtitle { parts.append(s) }
    parts += i.creators
    for s in [i.series, i.publisher, i.isbn, i.notes] {
        if let s { parts.append(s) }
    }
    parts += i.tags
    if let r = i.room { parts.append(r) }
    return fold(parts.joined(separator: " "))
}

public func applyFilters(_ items: [Item], _ f: Filters) -> [Item] {
    let words = fold(f.q).split(separator: " ").map(String.init).filter { !$0.isEmpty }
    return items.filter { i in
        if f.kind != "all", i.kind != f.kind { return false }
        if f.status != "all", i.status != f.status { return false }
        if f.format != "all", i.format != f.format { return false }
        if f.room != "all", (i.room ?? "") != f.room { return false }
        if f.category != "all", (i.category ?? "") != f.category { return false }
        if f.minRating > 0, i.rating < f.minRating { return false }
        switch f.scope {
        case "owned": if !i.owned { return false }
        case "wish": if i.owned { return false }
        case "lent": if i.openLoan == nil { return false }
        case "recommend": if !i.recommend { return false }
        case "check": if !i.needsCheck { return false }
        default: break
        }
        if !words.isEmpty {
            let hay = searchText(i)
            if !words.allSatisfy({ hay.contains($0) }) { return false }
        }
        return true
    }
}

/// Sort key for titles: ignore leading articles so "Der Koran" sorts under K.
public func titleKey(_ t: String) -> String {
    fold(Rx.articles.replace(t, ""))
}

/// Surname key: "Mai Thi Nguyen-Kim" → "nguyen kim", "Laura Lamping (Hg.)" → "lamping", "Schami, Rafik" → "schami".
public func creatorKey(_ i: Item) -> String {
    let c = Rx.parens.replace(i.creators.first ?? "", "").trimmed
    let surname = c.contains(",") ? (c.components(separatedBy: ",").first ?? "") : (Rx.spaces.split(c).last ?? "")
    return "\(fold(surname)) \(titleKey(i.title))"
}

/// Compare UTF-16 code units, like Dart's String.compareTo.
func compareUnits<A: Collection, B: Collection>(_ a: A, _ b: B) -> Int where A.Element == UInt16, B.Element == UInt16 {
    var x = a.makeIterator(), y = b.makeIterator()
    while true {
        switch (x.next(), y.next()) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (p?, q?): if p != q { return p < q ? -1 : 1 }
        }
    }
}

public func compareStrings(_ a: String, _ b: String) -> Int { compareUnits(a.utf16, b.utf16) }

private func isDigit(_ u: UInt16) -> Bool { u >= 48 && u <= 57 }

/// Runs of digits and non-digits.
private func runs(_ s: String) -> [[UInt16]] {
    var out: [[UInt16]] = []
    var cur: [UInt16] = []
    for u in s.utf16 {
        if let last = cur.last, isDigit(last) != isDigit(u) {
            out.append(cur)
            cur = []
        }
        cur.append(u)
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

private func numberValue(_ run: [UInt16]) -> Int? {
    guard !run.isEmpty, run.count <= 18, run.allSatisfy(isDigit) else { return nil }
    return run.reduce(0) { $0 * 10 + Int($1 - 48) }
}

/// Numbers inside strings compare by value ("Band 2" < "Band 10").
public func naturalCompare(_ a: String, _ b: String) -> Int {
    let ma = runs(a), mb = runs(b)
    for k in 0..<min(ma.count, mb.count) {
        let c: Int
        if let nx = numberValue(ma[k]), let ny = numberValue(mb[k]) {
            c = nx < ny ? -1 : (nx > ny ? 1 : 0)
        } else {
            c = compareUnits(ma[k], mb[k])
        }
        if c != 0 { return c }
    }
    return ma.count < mb.count ? -1 : (ma.count > mb.count ? 1 : 0)
}

public let sortKeys = ["title", "creator", "added", "rating", "year", "place"]

public func sortItems(_ items: [Item], _ key: String) -> [Item] {
    // keys are computed once per item, not per comparison
    typealias Row = (item: Item, title: String, extra: String)
    let rows: [Row] = items.map { i in
        let extra = key == "creator" ? creatorKey(i) : (key == "place" ? fold(i.room ?? "") : "")
        return (item: i, title: titleKey(i.title), extra: extra)
    }
    func byTitle(_ a: Row, _ b: Row) -> Int {
        let c = naturalCompare(a.title, b.title)
        return c != 0 ? c : naturalCompare(a.item.volume ?? "", b.item.volume ?? "")
    }
    let cmp: (Row, Row) -> Int
    switch key {
    case "creator":
        cmp = { naturalCompare($0.extra, $1.extra) }
    case "added":
        cmp = { compareStrings($1.item.addedAt, $0.item.addedAt) }
    case "rating":
        cmp = { $0.item.rating != $1.item.rating ? $1.item.rating - $0.item.rating : byTitle($0, $1) }
    case "year":
        cmp = { ($1.item.year ?? 0) - ($0.item.year ?? 0) }
    case "place":
        // items without a room come last
        cmp = { a, b in
            let na = a.item.room == nil, nb = b.item.room == nil
            if na != nb { return na ? 1 : -1 }
            let c = naturalCompare(a.extra, b.extra)
            return c != 0 ? c : byTitle(a, b)
        }
    default:
        cmp = byTitle
    }
    return rows.sorted { cmp($0, $1) < 0 }.map { $0.item }
}

/// Rooms with item counts ("" = not set); only owned physical items have a place.
public func summarizePlaces(_ items: [Item]) -> [(room: String, count: Int)] {
    var counts: [String: Int] = [:]
    for i in items where i.owned && i.format == "physical" {
        counts[i.room ?? "", default: 0] += 1
    }
    return counts.map { (room: $0.key, count: $0.value) }.sorted { a, b in
        if a.room.isEmpty { return false }
        if b.room.isEmpty { return true }
        return naturalCompare(fold(a.room), fold(b.room)) < 0
    }
}

/// Rooms to offer: the configured ones (or defaults) plus any used by items.
public func allRooms(_ items: [Item], _ configured: [String], _ defaults: [String]) -> [String] {
    var list = configured.isEmpty ? defaults : configured
    for i in items {
        if let r = i.room, !list.contains(r) { list.append(r) }
    }
    return list
}

/// Names used in earlier loans, most recent first.
public func knownPeople(_ items: [Item]) -> [String] {
    let loans = items.flatMap(\.loans).sorted { compareStrings($0.since, $1.since) > 0 }
    var seen = Set<String>()
    return loans.map(\.to).filter { seen.insert($0).inserted }
}

// MARK: - import / export

public func toExport(_ items: [Item]) -> JSONObject {
    ["app": "mybib", "version": 1, "exportedAt": nowISO(), "items": items.map { $0.toJSON() }]
}

public struct ImportError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Read an import file: a mybib export, a bare list of items, or `{ items: [...] }` (the format
/// the Claude skill produces). A top-level room applies to items without their own.
/// `"updateOnly": true` only completes books already in the catalogue.
public func parseImportFile(_ data: Data) throws -> (items: [Item], updateOnly: Bool) {
    let root = try decodeJSON(data)
    let top = root as? JSONObject ?? [:]
    let list: [Any] = (root as? [Any]) ?? (top["items"] as? [Any]) ?? []
    if list.isEmpty { throw ImportError(message: "no items") }
    let isExport = (top["app"] as? String) == "mybib"
    var items: [Item] = []
    for case let x as JSONObject in list where x["title"] is String {
        var m = x
        let ownRoom = flat(x["room"])
        let room: Any = ownRoom ?? flat(top["room"]) ?? NSNull()
        m["room"] = room
        let shelf: Any? = flat(x["shelf"]) ?? (ownRoom != nil ? nil : flat(top["shelf"]))
        m["shelf"] = shelf ?? NSNull()
        let source: Any = isExport ? (flat(x["source"]) ?? NSNull()) : "import"
        m["source"] = source
        items.append(normalizeItem(m))
    }
    return (items, jBool(top["updateOnly"]) == true)
}

public func parseImportFile(_ text: String) throws -> (items: [Item], updateOnly: Bool) {
    try parseImportFile(Data(text.utf8))
}

private let fillable = ["subtitle", "publisher", "year", "isbn", "language", "series", "volume", "pages", "description", "coverUrl", "category", "room", "ageFrom", "needsCheck"]

/// Copy of `old` with its empty fields filled from `inc`, or nil when nothing changes.
public func fillEmpty(_ old: Item, _ inc: Item) -> Item? {
    let o = old.toJSON(), n = inc.toJSON()
    var patch = JSONObject()
    for k in fillable {
        let ov = flat(o[k]), nv = flat(n[k])
        if ov == nil || (ov as? String) == "", let nv, (nv as? String) != "" { patch[k] = nv }
    }
    if old.tags.isEmpty, !inc.tags.isEmpty { patch["tags"] = inc.tags }
    if patch.isEmpty { return nil }
    patch["updatedAt"] = nowISO()
    return old.copyWith(patch)
}

public struct MergeResult {
    public let items: [Item]
    public let added: Int, updated: Int, skipped: Int
}

/// Merge imported items: same id → newer `updatedAt` wins; obvious duplicate → its empty fields
/// are filled in; otherwise added (unless `updateOnly`).
public func mergeItems(_ existing: [Item], _ incoming: [Item], updateOnly: Bool = false) -> MergeResult {
    var all = existing
    var idx: [String: Int] = [:]
    for (k, i) in all.enumerated() { idx[i.id] = k }
    var added = 0, updated = 0, skipped = 0
    for inc in incoming {
        if let k = idx[inc.id] {
            if compareStrings(inc.updatedAt, all[k].updatedAt) > 0 {
                all[k] = inc
                updated += 1
            } else {
                skipped += 1
            }
            continue
        }
        if let dup = findDuplicateOf(all, inc) {
            if let filled = fillEmpty(dup, inc), let k = idx[dup.id] {
                all[k] = filled
                updated += 1
            } else {
                skipped += 1
            }
            continue
        }
        if updateOnly {
            skipped += 1
            continue
        }
        idx[inc.id] = all.count
        all.append(inc)
        added += 1
    }
    return MergeResult(items: all, added: added, updated: updated, skipped: skipped)
}

private let csvColumns = ["kind", "title", "subtitle", "creators", "publisher", "year", "isbn", "language", "series", "volume", "format", "owned",
                          "status", "rating", "recommend", "category", "room", "lentTo", "tags", "notes", "addedAt"]

private func csvText(_ v: Any?) -> String {
    guard let v = flat(v) else { return "" }
    if let a = v as? [Any] { return a.map { csvText($0) }.joined(separator: ", ") }
    if let b = jBool(v) { return b ? "true" : "false" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return "\(v)"
}

/// Spreadsheet-friendly export (semicolon separated, as Excel in German locale expects).
public func toCSV(_ items: [Item]) -> String {
    func esc(_ v: Any?) -> String {
        let s = csvText(v)
        return Rx.csvSpecial.test(s) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
    let rows = items.map { i -> String in
        let j = i.toJSON()
        return csvColumns.map { c in esc(c == "lentTo" ? (i.openLoan?.to as Any?) : j[c]) }.joined(separator: ";")
    }
    return "\u{FEFF}" + ([csvColumns.joined(separator: ";")] + rows).joined(separator: "\n")
}

// MARK: - bulk completion

/// Details online sources can deliver that are still missing.
public func missingInfo(_ i: Item) -> [String] {
    var out: [String] = []
    if !i.hasCover { out.append("cover") }
    if i.publisher == nil { out.append("publisher") }
    if i.year == nil { out.append("year") }
    if i.isbn == nil { out.append("isbn") }
    if i.description == nil { out.append("description") }
    return out
}

/// Books that could still gain details; `retry` includes those already looked up.
public func bulkTargets(_ items: [Item], _ retry: Bool) -> [Item] {
    items.filter { $0.kind == "book" && !missingInfo($0).isEmpty && (retry || $0.lookedUp == nil) }
}
