import Foundation

/// An online search result: item fields plus the service it came from.
public struct Candidate: @unchecked Sendable {
    public var data: JSONObject
    public var via: String

    public init(_ data: JSONObject, _ via: String) {
        self.data = data
        self.via = via
    }

    public var title: String { flat(data["title"]) as? String ?? "" }
    public var creators: [String] { (flat(data["creators"]) as? [Any])?.compactMap { $0 as? String } ?? [] }
    public var coverUrl: String? { flat(data["coverUrl"]) as? String }
    public var kind: String { flat(data["kind"]) as? String ?? "book" }

    public func with(_ patch: JSONObject) -> Candidate { Candidate(data.merging(patch) { _, new in new }, via) }

    /// Item draft (JSON) from a candidate, ready for normalizeItem / the form.
    public func draft(source: String = "search") -> JSONObject {
        var d = data
        d["source"] = source
        return d
    }
}

private func year(_ v: Any?) -> Int? {
    guard let s = flat(v) as? String, let m = Rx.year.first(s) else { return nil }
    return Int(m)
}

private func firstObject(_ v: Any?) -> JSONObject? {
    (flat(v) as? [Any])?.first { $0 is JSONObject } as? JSONObject
}

private func strings(_ v: Any?) -> [String] {
    (flat(v) as? [Any])?.compactMap { $0 as? String } ?? []
}

private func names(_ v: Any?) -> [String] {
    (flat(v) as? [Any])?.compactMap { ($0 as? JSONObject)?["name"] as? String } ?? []
}

private let dvdFormat = Rx("dvd|blu-ray", caseInsensitive: true)
private let gameCategory = Rx("game|spiel", caseInsensitive: true)
private let musicCategory = Rx("music|cd", caseInsensitive: true)
private let isbn13Shape = Rx("^97[89][0-9]{10}$")

/// Google Books, Open Library, MusicBrainz + Cover Art Archive and UPCitemdb.
public final class Lookup: @unchecked Sendable {
    public static let shared = Lookup()

    public var http: any HTTPClient
    private let lock = NSLock()
    private var googleProblem = ""
    private let timeout: TimeInterval = 12

    public init(http: any HTTPClient = URLSessionHTTP()) {
        self.http = http
    }

    /// Last problem Google Books reported: "" = fine, "quota" = daily limit reached, "key" = key rejected.
    public func takeGoogleProblem() -> String {
        lock.lock()
        defer { lock.unlock() }
        let p = googleProblem
        googleProblem = ""
        return p
    }

    private func setGoogleProblem(_ p: String) {
        lock.lock()
        googleProblem = p
        lock.unlock()
    }

    private func getJSON(_ url: String) async -> (Int, Any?) {
        guard let u = URL(string: url) else { return (0, nil) }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("mybib/1.0 (https://github.com/nevbie/mybib)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, res) = try await http.send(req)
            if res.statusCode != 200 { return (res.statusCode, nil) }
            return (200, try decodeJSON(data))
        } catch {
            return (0, nil)
        }
    }

    /// True when the URL is a real image (Open Library / Cover Art Archive answer 404 for "no cover").
    public func probeImage(_ url: String) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = "HEAD"
        guard let reply = try? await http.send(req) else { return false }
        let res = reply.1
        let type = res.value(forHTTPHeaderField: "Content-Type") ?? ""
        let len = Int(res.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 1000
        return res.statusCode == 200 && type.hasPrefix("image/") && len > 200
    }

    // MARK: Google Books

    private func fromGoogle(_ v: Any) -> Candidate? {
        guard let v = v as? JSONObject, let i = v["volumeInfo"] as? JSONObject, i["title"] is String else { return nil }
        var isbn: String?
        for case let x as JSONObject in (i["industryIdentifiers"] as? [Any]) ?? [] where (x["type"] as? String) == "ISBN_13" {
            isbn = x["identifier"] as? String
        }
        let links = i["imageLinks"] as? JSONObject
        let thumb = (flat(links?["thumbnail"]) ?? flat(links?["smallThumbnail"])) as? String
        var cover: String?
        if let thumb {
            var t = thumb
            if let r = t.range(of: "http:") { t.replaceSubrange(r, with: "https:") }
            cover = t.replacingOccurrences(of: "&edge=curl", with: "")
        }
        let pages = jInt(i["pageCount"]).flatMap { $0 > 0 ? $0 : nil }
        let d: [String: Any?] = [
            "kind": "book",
            "title": i["title"],
            "subtitle": i["subtitle"],
            "creators": strings(i["authors"]),
            "publisher": i["publisher"],
            "year": year(i["publishedDate"]),
            "description": i["description"],
            "pages": pages,
            "language": i["language"],
            "isbn": isbn,
            "coverUrl": cover,
        ]
        return Candidate(compact(d), "Google Books")
    }

    private func google(_ q: String, _ key: String, max: Int = 8) async -> [Candidate] {
        var url = "https://www.googleapis.com/books/v1/volumes?q=\(encodeQuery(q))&maxResults=\(max)&printType=books"
        if !key.isEmpty { url += "&key=\(encodeQuery(key))" }
        let (status, data) = await getJSON(url)
        if status == 429 { setGoogleProblem("quota") }
        if status == 400 || status == 403, !key.isEmpty { setGoogleProblem("key") }
        let items = ((data as? JSONObject)?["items"] as? [Any]) ?? []
        return items.compactMap { fromGoogle($0) }
    }

    // MARK: Open Library

    private func openLibraryIsbn(_ isbn: String) async -> Candidate? {
        let (_, data) = await getJSON("https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")
        guard let b = (data as? JSONObject)?["ISBN:\(isbn)"] as? JSONObject, b["title"] is String else { return nil }
        let cover = b["cover"] as? JSONObject
        let d: [String: Any?] = [
            "kind": "book",
            "title": b["title"],
            "subtitle": b["subtitle"],
            "creators": names(b["authors"]),
            "publisher": firstObject(b["publishers"])?["name"],
            "year": year(b["publish_date"]),
            "pages": b["number_of_pages"],
            "isbn": isbn,
            "coverUrl": flat(cover?["medium"]) ?? flat(cover?["large"]),
        ]
        return Candidate(compact(d), "Open Library")
    }

    private func openLibrarySearch(_ params: String) async -> [Candidate] {
        let fields = "title,subtitle,author_name,first_publish_year,publisher,isbn,cover_i,language,number_of_pages_median"
        let (_, data) = await getJSON("https://openlibrary.org/search.json?\(params)&limit=8&fields=\(fields)")
        let docs = ((data as? JSONObject)?["docs"] as? [Any]) ?? []
        return docs.compactMap { doc -> Candidate? in
            guard let d = doc as? JSONObject, d["title"] is String else { return nil }
            let isbns = strings(d["isbn"])
            let coverId = jStr(d["cover_i"])
            let m: [String: Any?] = [
                "kind": "book",
                "title": d["title"],
                "subtitle": d["subtitle"],
                "creators": strings(d["author_name"]),
                "year": d["first_publish_year"],
                "publisher": (flat(d["publisher"]) as? [Any])?.first,
                "isbn": isbns.first(where: { $0.count == 13 && $0.hasPrefix("97") }),
                "pages": d["number_of_pages_median"],
                "language": (flat(d["language"]) as? [Any])?.first,
                "coverUrl": coverId.map { "https://covers.openlibrary.org/b/id/\($0)-M.jpg" },
            ]
            return Candidate(compact(m), "Open Library")
        }
    }

    // MARK: MusicBrainz, UPCitemdb

    private func musicbrainz(_ query: String) async -> [Candidate] {
        let (_, data) = await getJSON("https://musicbrainz.org/ws/2/release/?query=\(encodeQuery(query))&fmt=json&limit=8")
        let releases = ((data as? JSONObject)?["releases"] as? [Any]) ?? []
        return releases.compactMap { rel -> Candidate? in
            guard let r = rel as? JSONObject else { return nil }
            let fmt = firstObject(r["media"])?["format"] as? String ?? ""
            let barcode = r["barcode"] as? String
            let label = firstObject(r["label-info"])?["label"] as? JSONObject
            let m: [String: Any?] = [
                "kind": dvdFormat.test(fmt) ? "dvd" : "cd",
                "title": r["title"],
                "creators": names(r["artist-credit"]),
                "publisher": label?["name"],
                "year": year(r["date"]),
                "isbn": barcode?.nonEmpty,
                "coverUrl": "https://coverartarchive.org/release/\(jStr(r["id"]) ?? "")/front-250",
            ]
            return Candidate(compact(m), "MusicBrainz")
        }
    }

    private func upcitemdb(_ ean: String) async -> [Candidate] {
        let (_, data) = await getJSON("https://api.upcitemdb.com/prod/trial/lookup?upc=\(ean)")
        let items = ((data as? JSONObject)?["items"] as? [Any]) ?? []
        return items.compactMap { raw -> Candidate? in
            guard let x = raw as? JSONObject, x["title"] is String else { return nil }
            let cat = x["category"] as? String ?? ""
            let kind = gameCategory.test(cat) ? "game" : (musicCategory.test(cat) ? "cd" : "dvd")
            let m: [String: Any?] = [
                "kind": kind,
                "title": x["title"],
                "creators": [String](),
                "publisher": x["brand"],
                "isbn": ean,
                "coverUrl": strings(x["images"]).first(where: { $0.hasPrefix("https:") }),
            ]
            return Candidate(compact(m), "UPCitemdb")
        }
    }

    // MARK: public API

    /// Fill gaps in `a` with values from `b` (same book from a second service).
    public func mergeCandidate(_ a: Candidate, _ b: Candidate) -> Candidate {
        var out = a.data
        for (k, v) in b.data where isEmptyValue(out[k]) { out[k] = v }
        return Candidate(out, a.via == b.via ? a.via : "\(a.via) + \(b.via)")
    }

    public func withWorkingCover(_ c: Candidate) async -> Candidate {
        guard let url = c.coverUrl else { return c }
        let ok = await probeImage(url)
        if !ok {
            var d = c.data
            d.removeValue(forKey: "coverUrl")
            return Candidate(d, c.via)
        }
        return c
    }

    /// Look up an ISBN in Google Books and Open Library, merged into one result.
    public func lookupIsbn(_ isbn: String, googleKey: String = "") async -> Candidate? {
        async let gs = self.google("isbn:\(isbn)", googleKey, max: 1)
        async let ols = self.openLibraryIsbn(isbn)
        let g = await gs.first
        let ol = await ols
        var c: Candidate
        if let g, let ol {
            // Open Library covers are larger and have no "preview" banner; Google usually has the better text.
            var patch = JSONObject()
            if let u = ol.coverUrl { patch["coverUrl"] = u }
            c = mergeCandidate(g.with(patch), ol)
        } else if let one = g ?? ol {
            c = one
        } else {
            return nil
        }
        c = c.with(["isbn": isbn])
        if c.coverUrl == nil {
            let fallback = "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg?default=false"
            return await probeImage(fallback) ? c.with(["coverUrl": fallback]) : c
        }
        return await withWorkingCover(c)
    }

    /// Look up a non-ISBN barcode (CD, DVD, game).
    public func lookupEan(_ ean: String) async -> [Candidate] {
        let mb = await musicbrainz("barcode:\(ean)")
        var list = mb
        if list.isEmpty { list = await upcitemdb(ean) }
        return await concurrentMap(Array(list.prefix(5))) { await self.withWorkingCover($0) }
    }

    /// Google Books + Open Library by title / author, merged; covers not checked yet.
    public func searchBooks(_ title: String, _ creator: String, googleKey: String = "") async -> [Candidate] {
        var gq: [String] = []
        var olq: [String] = []
        if !title.isEmpty {
            gq.append("intitle:\(title)")
            olq.append("title=\(encodeQuery(title))")
        }
        if !creator.isEmpty {
            gq.append("inauthor:\(creator)")
            olq.append("author=\(encodeQuery(creator))")
        }
        async let g = self.google(gq.joined(separator: " "), googleKey)
        async let ol = self.openLibrarySearch(olq.joined(separator: "&"))
        let gList = await g
        let olList = await ol
        let all = gList + olList
        return dedupe(all)
    }

    /// Free-text search by title / creator for the chosen kind.
    public func searchOnline(_ kind: String, _ title: String, _ creator: String, googleKey: String = "") async -> [Candidate] {
        let title = title.trimmed, creator = creator.trimmed
        if title.isEmpty && creator.isEmpty { return [] }
        var list: [Candidate] = []
        if kind == "book" {
            list = await searchBooks(title, creator, googleKey: googleKey)
        } else if kind == "cd" || kind == "dvd" {
            var q: [String] = []
            if !title.isEmpty { q.append("release:\"\(title.replacingOccurrences(of: "\"", with: ""))\"") }
            if !creator.isEmpty { q.append("artist:\"\(creator.replacingOccurrences(of: "\"", with: ""))\"") }
            list = await musicbrainz(q.joined(separator: " AND "))
            if kind == "dvd" { list = list.filter { $0.kind == "dvd" } + list.filter { $0.kind != "dvd" } }
        }
        return await concurrentMap(Array(list.prefix(10))) { await self.withWorkingCover($0) }
    }

    private func dedupe(_ list: [Candidate]) -> [Candidate] {
        var out: [Candidate] = []
        func key(_ c: Candidate) -> String { "\(fold(c.title))|\(fold(c.creators.first ?? ""))" }
        for c in list {
            if let i = out.firstIndex(where: { key($0) == key(c) }) {
                out[i] = mergeCandidate(out[i], c)
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// Best online match for a catalogued item: by ISBN if it has one, otherwise by title + author;
    /// accepted only when the title (and author, if known) clearly match.
    public func findBestMatch(_ item: Item, googleKey: String = "") async -> Candidate? {
        if let isbn = item.isbn, isbn13Shape.test(isbn), let c = await lookupIsbn(isbn, googleKey: googleKey) {
            return c
        }
        let list = await searchBooks(item.title, item.creators.first ?? "", googleKey: googleKey)
        // without a known author only an (almost) identical title counts – in both directions
        let minScore = item.creators.isEmpty ? 0.95 : 0.75
        var best: Candidate?
        var bestScore = 0.0
        for c in list {
            let s = item.creators.isEmpty ? titleOverlap(item.title, c.title) : matchScore(item.title, item.creators, c)
            if s > bestScore {
                best = c
                bestScore = s
            }
        }
        guard let best, bestScore >= minScore else { return nil }
        return await withWorkingCover(best)
    }
}

private func words(_ s: String) -> Set<String> {
    Set(fold(s).split(separator: " ").map(String.init).filter { $0.count > 1 })
}

/// How well does an online result match what we know (e.g. from a spine photo)? 0…1
public func matchScore(_ title: String, _ creators: [String], _ c: Candidate) -> Double {
    let a = words(title)
    let sub = jStr(c.data["subtitle"]) ?? ""
    let b = words("\(c.title) \(sub)")
    if a.isEmpty { return 0 }
    var score = Double(a.filter { b.contains($0) }.count) / Double(a.count)
    if let first = creators.first {
        let last = fold(first).components(separatedBy: " ").last ?? ""
        let has = c.creators.contains { fold($0).contains(last) }
        score = score * 0.7 + (has ? 0.3 : 0)
    }
    return score
}

/// Share of words the two titles have in common (Jaccard), 0…1.
public func titleOverlap(_ a: String, _ b: String) -> Double {
    let x = Set(fold(a).split(separator: " ").map(String.init))
    let y = Set(fold(b).split(separator: " ").map(String.init))
    if x.isEmpty || y.isEmpty { return 0 }
    let common = x.intersection(y).count
    return Double(common) / Double(x.count + y.count - common)
}

/// Fill only the fields the item doesn't have yet from an online result.
public func enrichPatch(_ item: JSONObject, _ c: Candidate) -> JSONObject {
    var patch = JSONObject()
    for k in ["subtitle", "publisher", "year", "isbn", "pages", "description", "coverUrl", "language"] {
        if isEmptyValue(item[k]), !isEmptyValue(c.data[k]), let v = flat(c.data[k]) { patch[k] = v }
    }
    if isEmptyValue(item["creators"]), !c.creators.isEmpty { patch["creators"] = c.creators }
    return patch
}
