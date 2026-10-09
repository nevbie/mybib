import Foundation
import Observation

/// All data lives on this device: one JSON file for the catalogue, one for settings.
/// Writes are debounced so typing a note doesn't rewrite the file on every key.
@MainActor
@Observable
public final class Store {
    public private(set) var items: [Item] = []
    public private(set) var settings = Settings()
    public private(set) var ready = false

    /// Directory for the data files; the app's documents directory when nil (tests pass a temp dir).
    public let dir: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(dir: URL? = nil) {
        self.dir = dir
    }

    private func file(_ name: String) -> URL {
        let base = dir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(name)
    }

    public func byId(_ id: String) -> Item? { items.first { $0.id == id } }

    public func load() {
        do {
            let f = file("items.json")
            if FileManager.default.fileExists(atPath: f.path) {
                let data = try decodeJSON(Data(contentsOf: f)) as? JSONObject
                items = ((data?["items"] as? [Any]) ?? []).compactMap { $0 as? JSONObject }.map { normalizeItem($0) }
            }
            let s = file("settings.json")
            if FileManager.default.fileExists(atPath: s.path), let j = try decodeJSON(Data(contentsOf: s)) as? JSONObject {
                settings = Settings(json: j)
            }
        } catch {
            print("loading failed: \(error)")
        }
        ready = true
    }

    private func changed() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.save()
        }
    }

    /// Write the catalogue now (atomically: temp file, then rename).
    public func save() {
        saveTask?.cancel()
        saveTask = nil
        guard ready else { return }
        do {
            let data = try encodeJSON(["version": 1, "items": items.map { $0.toJSON() }] as JSONObject)
            try data.write(to: file("items.json"), options: .atomic)
        } catch {
            print("saving failed: \(error)")
        }
    }

    @discardableResult
    public func addItems(_ drafts: [JSONObject]) -> [Item] {
        let now = nowISO()
        let created = drafts.map { d -> Item in
            var m = d
            m["id"] = NSNull()
            m["addedAt"] = now
            m["updatedAt"] = now
            return normalizeItem(m)
        }
        items += created
        changed()
        return created
    }

    public func updateItem(_ id: String, _ patch: JSONObject) {
        updateItems([id]) { _ in patch }
    }

    /// Apply a (per-item) change to many items at once – bulk edit, room/category moves.
    public func updateItems(_ ids: [String], _ patch: (Item) -> JSONObject) {
        let set = Set(ids)
        let now = nowISO()
        items = items.map { i in
            guard set.contains(i.id) else { return i }
            var p = patch(i)
            p["id"] = i.id
            p["updatedAt"] = now
            return i.copyWith(p)
        }
        changed()
    }

    public func removeItems(_ ids: [String]) {
        let set = Set(ids)
        items = items.filter { !set.contains($0.id) }
        changed()
    }

    @discardableResult
    public func importItems(_ incoming: [Item], updateOnly: Bool = false) -> MergeResult {
        let r = mergeItems(items, incoming, updateOnly: updateOnly)
        items = r.items
        changed()
        return r
    }

    public func replaceAll(_ list: [Item]) {
        items = list
        changed()
    }

    public func moveRoom(_ from: String, _ to: String) {
        let value: Any = to.isEmpty ? NSNull() : to
        updateItems(items.filter { ($0.room ?? "") == from }.map(\.id)) { _ in ["room": value] }
    }

    public func moveCategory(_ from: String, _ to: String) {
        let value: Any = to.isEmpty ? NSNull() : to
        updateItems(items.filter { $0.category == from }.map(\.id)) { _ in ["category": value] }
    }

    public func updateSettings(_ s: Settings) {
        settings = s
        do {
            try encodeJSON(s.toJSON()).write(to: file("settings.json"), options: .atomic)
        } catch {
            print("saving settings failed: \(error)")
        }
    }

    public func rooms(lang: String) -> [String] {
        allRooms(items, settings.rooms, defaultRooms.map { lang == "de" ? $0[0] : $0[1] })
    }

    public func categories() -> [String] {
        allCategories(settings.categories, items.map(\.category))
    }
}
