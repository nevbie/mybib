import Foundation

/// What kind of thing sits on the shelf.
public let kinds = ["book", "game", "dvd", "cd"]

/// Physical copy, e-book or audiobook (only meaningful for books).
public let formats = ["physical", "ebook", "audio"]

/// Reading (playing, watching, listening) status. `want` = want to read, `done` = read.
public let statuses = ["none", "want", "active", "done"]

public let sources = ["manual", "isbn", "search", "ai", "import"]

public struct Loan: Equatable, Hashable, Sendable {
    public let to: String
    /// ISO date YYYY-MM-DD
    public let since: String
    /// ISO date when it came back; nil while it is still lent out
    public let returned: String?

    public init(to: String, since: String, returned: String? = nil) {
        self.to = to
        self.since = since
        self.returned = returned
    }

    public func toJSON() -> JSONObject {
        var m: JSONObject = ["to": to, "since": since]
        if let returned { m["returned"] = returned }
        return m
    }
}

/// Local date YYYY-MM-DD.
public func today() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

/// UTC timestamp like JavaScript's toISOString(): 2026-10-09T05:07:12.345Z
public func nowISO() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}

public func newId() -> String {
    let ms = Int(Date().timeIntervalSince1970 * 1000)
    let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    return String(ms, radix: 36) + String((0..<6).map { _ in chars[Int.random(in: 0..<36)] })
}

/// One catalogue entry. Same JSON format as the web and Android app, so backups move between all of them.
public struct Item: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let subtitle: String?
    /// authors, artists, directors or game designers
    public let creators: [String]
    public let publisher: String?
    public let year: Int?
    /// ISBN-13 for books, EAN / UPC for everything else
    public let isbn: String?
    public let language: String?
    public let series: String?
    public let volume: String?
    public let pages: Int?
    public let description: String?
    /// remote cover (Open Library, Google Books, Cover Art Archive)
    public let coverUrl: String?
    /// own photo, downscaled JPEG data URL – wins over coverUrl
    public let coverData: String?
    public let tags: [String]
    /// one main category: a default id (see Categories.swift) or an own name
    public let category: String?
    public let format: String
    /// false = wishlist (not owned yet)
    public let owned: Bool
    public let status: String
    /// 0 = not rated, 1–5 stars
    public let rating: Int
    public let recommend: Bool
    public let notes: String?
    public let room: String?
    public let playersMin: Int?
    public let playersMax: Int?
    public let playMinutes: Int?
    public let ageFrom: Int?
    /// all loans, newest last; the open one has no `returned`
    public let loans: [Loan]
    /// set by the photo recognition when it is unsure – shown as "please check"
    public let needsCheck: Bool
    /// date of the last automatic online lookup, so bulk completion doesn't retry every time
    public let lookedUp: String?
    public let source: String
    public let addedAt: String
    public let updatedAt: String

    public var openLoan: Loan? { loans.first { $0.returned == nil } }
    public var hasCover: Bool { coverData != nil || coverUrl != nil }

    /// JSON as stored and exported; nil fields are left out, needsCheck only when set.
    public func toJSON() -> JSONObject {
        var m: JSONObject = [
            "id": id, "kind": kind, "title": title, "creators": creators, "tags": tags,
            "format": format, "owned": owned, "status": status, "rating": rating, "recommend": recommend,
            "source": source, "addedAt": addedAt, "updatedAt": updatedAt,
        ]
        m["loans"] = loans.map { $0.toJSON() }
        let optional: [String: Any?] = [
            "subtitle": subtitle, "publisher": publisher, "year": year, "isbn": isbn, "language": language,
            "series": series, "volume": volume, "pages": pages, "description": description,
            "coverUrl": coverUrl, "coverData": coverData, "category": category, "notes": notes, "room": room,
            "playersMin": playersMin, "playersMax": playersMax, "playMinutes": playMinutes, "ageFrom": ageFrom,
            "lookedUp": lookedUp,
        ]
        for (k, v) in optional {
            if let v = flat(v) { m[k] = v }
        }
        if needsCheck { m["needsCheck"] = true }
        return m
    }

    /// Change some fields; a key with value NSNull() removes that optional value.
    public func copyWith(_ patch: JSONObject) -> Item {
        normalizeItem(toJSON().merging(patch) { _, new in new })
    }
}

private func oneOf(_ list: [String], _ v: Any?, _ fallback: String) -> String {
    if let s = flat(v) as? String, list.contains(s) { return s }
    return fallback
}

/// Only rooms are kept. Older data may still carry a shelf: the photo import put everything
/// in room "Foto-Import" with shelves "Foto 1" … – those shelves become rooms.
private func roomOf(_ r: JSONObject) -> String? {
    let room = jStr(r["room"])
    let shelf = jStr(r["shelf"])
    if let shelf, room == nil || room == "Foto-Import" { return shelf }
    return room
}

/// Turn anything that looks roughly like an item (form draft, AI result, imported JSON)
/// into a complete, valid Item. Unknown fields are dropped.
public func normalizeItem(_ r: JSONObject, now: String? = nil) -> Item {
    let now = now ?? nowISO()
    var loans: [Loan] = []
    if let list = flat(r["loans"]) as? [Any] {
        for l in list {
            if let loan = l as? Loan {
                loans.append(loan)
            } else if let m = l as? JSONObject, let to = jStr(m["to"]) {
                loans.append(Loan(to: to, since: jStr(m["since"]) ?? today(), returned: jStr(m["returned"])))
            }
        }
    }
    var coverData: String?
    if let c = flat(r["coverData"]) as? String, c.hasPrefix("data:image/") { coverData = c }
    let isbn = jStr(r["isbn"]).map { Rx.notIsbnChar.replace($0, "") }
    let creators = flat(r["creators"]) ?? flat(r["authors"]) ?? flat(r["author"])
    return Item(
        id: jStr(r["id"]) ?? newId(),
        kind: oneOf(kinds, r["kind"], "book"),
        title: jStr(r["title"]) ?? "?",
        subtitle: jStr(r["subtitle"]),
        creators: jStrList(creators),
        publisher: jStr(r["publisher"]),
        year: jInt(r["year"]),
        isbn: isbn?.nonEmpty,
        language: jStr(r["language"]),
        series: jStr(r["series"]),
        volume: jStr(r["volume"]),
        pages: jInt(r["pages"]),
        description: jStr(r["description"]),
        coverUrl: jStr(r["coverUrl"]),
        coverData: coverData,
        tags: jStrList(r["tags"]),
        category: toCategory(jStr(r["category"])),
        format: oneOf(formats, r["format"], "physical"),
        owned: jBool(r["owned"]) != false,
        status: oneOf(statuses, r["status"], "none"),
        rating: min(5, max(0, jInt(r["rating"]) ?? 0)),
        recommend: jBool(r["recommend"]) == true,
        notes: jStr(r["notes"]),
        room: roomOf(r),
        playersMin: jInt(r["playersMin"]),
        playersMax: jInt(r["playersMax"]),
        playMinutes: jInt(r["playMinutes"]),
        ageFrom: jInt(r["ageFrom"]),
        loans: loans,
        needsCheck: jBool(r["needsCheck"]) == true,
        lookedUp: jStr(r["lookedUp"]),
        source: oneOf(sources, r["source"], "manual"),
        addedAt: jStr(r["addedAt"]) ?? now,
        updatedAt: jStr(r["updatedAt"]) ?? now
    )
}

public struct Settings: Equatable, Sendable {
    public var claudeKey: String
    public var claudeModel: String
    public var googleBooksKey: String
    public var lastRoom: String
    /// rooms shown even when empty; [] = the default rooms
    public var rooms: [String]
    /// category list in display order; [] = the default categories
    public var categories: [String]
    /// "de" or "en"; nil = phone language
    public var lang: String?

    public init(claudeKey: String = "", claudeModel: String = "claude-opus-5-5", googleBooksKey: String = "", lastRoom: String = "",
                rooms: [String] = [], categories: [String] = [], lang: String? = nil) {
        self.claudeKey = claudeKey
        self.claudeModel = claudeModel
        self.googleBooksKey = googleBooksKey
        self.lastRoom = lastRoom
        self.rooms = rooms
        self.categories = categories
        self.lang = lang
    }

    public init(json j: JSONObject) {
        self.init(
            claudeKey: jStr(j["claudeKey"]) ?? "",
            claudeModel: jStr(j["claudeModel"]) ?? "claude-opus-5-5",
            googleBooksKey: jStr(j["googleBooksKey"]) ?? "",
            lastRoom: jStr(j["lastRoom"]) ?? "",
            rooms: jStrList(j["rooms"]),
            categories: jStrList(j["categories"]),
            lang: jStr(j["lang"])
        )
    }

    public func toJSON() -> JSONObject {
        var m: JSONObject = [
            "claudeKey": claudeKey, "claudeModel": claudeModel, "googleBooksKey": googleBooksKey,
            "lastRoom": lastRoom, "rooms": rooms, "categories": categories,
        ]
        if let lang { m["lang"] = lang }
        return m
    }
}

public let defaultRooms = [
    ["Küche", "Kitchen"],
    ["Wohnzimmer", "Living room"],
    ["Kleines Zimmer", "Small room"],
]
