import SwiftUI
import MybibCore

private let searchable = ["book", "cd", "dvd"]

/// Search Google Books / Open Library / MusicBrainz and hand back the picked result.
struct SearchSheet: View {
    let kind: String
    let title: String
    let creator: String
    let onPick: (Candidate) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var k = "book"
    @State private var t = ""
    @State private var c = ""
    @State private var busy = false
    @State private var results: [Candidate]?
    @State private var started = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(model.t("field.kind"), selection: $k) {
                        ForEach(searchable, id: \.self) { Text(model.t("kind.\($0)")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledField(label: model.t("field.title"), text: $t).submitLabel(.search).onSubmit(run)
                    LabeledField(label: model.t("creator.\(k)"), text: $c).submitLabel(.search).onSubmit(run)
                    Button(action: run) {
                        Label(busy ? model.t("search.busy") : model.t("search.go"), systemImage: "magnifyingglass")
                    }
                    .disabled(busy)
                }
                if busy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let results, results.isEmpty {
                    Text(model.t("search.none"))
                }
                ForEach(Array((results ?? []).enumerated()), id: \.offset) { _, cand in
                    Button {
                        onPick(cand)
                        dismiss()
                    } label: {
                        CandidateRow(candidate: cand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(model.t("search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.cancelText) { dismiss() }
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            k = searchable.contains(kind) ? kind : "book"
            t = title
            c = creator
            if !title.trimmed.isEmpty { run() }
        }
    }

    private func run() {
        if t.trimmed.isEmpty && c.trimmed.isEmpty { return }
        let (kind, title, creator, key) = (k, t, c, model.settings.googleBooksKey)
        busy = true
        results = nil
        Task { @MainActor in
            let r = await Lookup.shared.searchOnline(kind, title, creator, googleKey: key)
            busy = false
            results = r
        }
    }
}

/// Cover and details of an online result.
struct CandidateRow: View {
    let candidate: Candidate
    var large = false

    var body: some View {
        let c = candidate
        let meta = [jStr(c.data["publisher"]), jStr(c.data["year"]), jStr(c.data["language"]), c.via].compactMap { $0 }
        HStack(alignment: .top, spacing: 12) {
            CoverImage(title: c.title, kind: c.kind, coverUrl: c.coverUrl, large: large)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).fontWeight(.semibold)
                if let s = jStr(c.data["subtitle"]) { Text(s) }
                Text(c.creators.joined(separator: ", "))
                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
