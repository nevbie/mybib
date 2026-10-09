import Foundation
import Observation
import MybibCore

/// App-wide state: the store plus UI state that outlives a screen (language, tab, filters).
@MainActor
@Observable
final class AppModel {
    let store: Store
    let strings: Strings
    let dialogs = DialogCenter()
    /// one navigation stack per tab
    let routers: [Router] = [Router(), Router(), Router(), Router()]
    var tab = 0
    var filters = Filters()
    var sort = "title"
    /// shows the file picker for an import (Add tab and Settings)
    var importing = false

    init(store: Store = Store()) {
        self.store = store
        strings = Strings.load(Bundle.main.url(forResource: "strings", withExtension: "json"))
        store.load()
    }

    var settings: MybibCore.Settings { store.settings }

    var lang: String {
        if let l = store.settings.lang, l == "de" || l == "en" { return l }
        return (Locale.preferredLanguages.first ?? "de").hasPrefix("en") ? "en" : "de"
    }

    func t(_ key: String, _ vars: [String: Any] = [:]) -> String { strings.t(lang, key, vars) }
    func catLabel(_ c: String) -> String { categoryLabel(c, lang) }
    var cancelText: String { lang == "de" ? "Abbrechen" : "Cancel" }
    var rooms: [String] { store.rooms(lang: lang) }

    func updateSettings(_ change: (inout MybibCore.Settings) -> Void) {
        var s = store.settings
        change(&s)
        store.updateSettings(s)
    }

    /// Jump to the library showing only what matches `f`.
    func showInLibrary(_ f: Filters, sortBy: String? = nil) {
        filters = f
        if let sortBy { sort = sortBy }
        routers[0].path = []
        tab = 0
    }

    /// Read a JSON file (backup, Claude import or update file) and merge it into the catalogue.
    func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let r = try parseImportFile(Data(contentsOf: url))
            let m = store.importItems(r.items, updateOnly: r.updateOnly)
            await dialogs.info(t("data.imported", ["added": m.added, "updated": m.updated, "skipped": m.skipped]))
        } catch {
            await dialogs.info(t("data.importError", ["e": error.localizedDescription]))
        }
    }
}
