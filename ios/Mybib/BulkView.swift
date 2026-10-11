import SwiftUI
import UIKit
import MybibCore

/// Complete covers, publisher, year, ISBN and blurb of all books via Google Books (+ Open Library).
struct BulkView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var retry = false
    @State private var stop = false
    /// idle / running / done / stopped / quota / key
    @State private var phase = "idle"
    @State private var done = 0
    @State private var total = 0
    @State private var current = ""
    @State private var found: [Item] = []
    @State private var missed: [Item] = []

    var body: some View {
        let items = model.store.items
        let targets = bulkTargets(items, retry)
        let triedBefore = bulkTargets(items, true).count - bulkTargets(items, false).count
        let running = phase == "running"
        List {
            Section {
                Text(model.t("bulk.intro")).font(.caption).foregroundStyle(.secondary)
                if model.settings.googleBooksKey.isEmpty {
                    NoteBox {
                        Text(model.t("bulk.noKey")).font(.subheadline)
                        Button(model.t("nav.settings")) {
                            router.pop()
                            model.tab = 3
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if phase == "idle" {
                    Text(targets.isEmpty ? model.t("bulk.nothing") : model.t("bulk.count", ["n": targets.count]))
                    if triedBefore > 0 {
                        Toggle(model.t("bulk.retry", ["n": triedBefore]), isOn: $retry)
                    }
                } else {
                    progress(running: running)
                }
            }
            if !found.isEmpty {
                Section(model.t("bulk.found", ["n": found.count])) {
                    ForEach(Array(found.reversed().prefix(30))) { i in link(i, withMissing: false) }
                }
            }
            if !missed.isEmpty && !running {
                Section {
                    ForEach(Array(missed.prefix(500))) { i in link(i, withMissing: true) }
                } header: {
                    Text(model.t("bulk.missed", ["n": missed.count]))
                } footer: {
                    Text(model.t("bulk.missedHint"))
                }
            }
        }
        .navigationTitle(model.t("bulk.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if running {
                    Button {
                        stop = true
                    } label: {
                        Text("■ \(model.t("bulk.stop"))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await run(targets) }
                    } label: {
                        Text(model.t("bulk.start", ["n": targets.count])).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(targets.isEmpty)
                }
            }
            .controlSize(.large)
            .padding(12)
            .background(.bar)
        }
        .onDisappear {
            // stop only when this screen was closed, not when an item was opened on top of it
            if !router.path.contains(.bulk) { stop = true }
        }
    }

    @ViewBuilder
    private func progress(running: Bool) -> some View {
        ProgressView(value: total == 0 ? 0 : Double(done) / Double(total))
        Text("\(done) / \(total) · ✓ \(found.count) · – \(missed.count)")
        if running && !current.isEmpty {
            Text(current).font(.caption).foregroundStyle(.secondary)
        }
        if phase == "done" { Text(model.t("bulk.done", ["found": found.count, "missed": missed.count])) }
        if phase == "stopped" { Text(model.t("bulk.stopped")) }
        if phase == "quota" || phase == "key" {
            NoteBox { Text(model.t(phase == "quota" ? "bulk.quota" : "bulk.badKey")) }
        }
    }

    private func link(_ i: Item, withMissing: Bool) -> some View {
        Button {
            router.push(.item(i.id))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).foregroundStyle(brandColor)
                if withMissing {
                    Text("(\(missingInfo(i).map { model.t("bulk.field.\($0)") }.joined(separator: ", ")))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func run(_ targets: [Item]) async {
        let lookup = Lookup.shared
        let key = model.settings.googleBooksKey
        stop = false
        _ = lookup.takeGoogleProblem()
        phase = "running"
        total = targets.count
        done = 0
        found = []
        missed = []
        // don't let the phone sleep while it works through hundreds of books
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        for (n, item) in targets.enumerated() {
            if stop {
                phase = "stopped"
                return
            }
            current = item.title
            let best = await lookup.findBestMatch(item, googleKey: key)
            let problem = lookup.takeGoogleProblem()
            if !problem.isEmpty && best == nil {
                // leave this item untried so the next run picks it up again
                phase = problem
                return
            }
            if let best {
                let patch = enrichPatch(item.toJSON(), best)
                var p = patch
                p["lookedUp"] = today()
                // without a known author a title-only match may be a different book – ask to check
                if item.creators.isEmpty { p["needsCheck"] = true }
                model.store.updateItem(item.id, p)
                if patch.isEmpty { missed.append(item) } else { found.append(item) }
            } else {
                model.store.updateItem(item.id, ["lookedUp": today()])
                missed.append(item)
            }
            done = n + 1
            if !problem.isEmpty {
                phase = problem
                return
            }
            // stay well below Google's per-minute limit
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        phase = "done"
    }
}
