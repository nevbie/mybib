import SwiftUI
import UIKit
import MybibCore

private struct PhotoRow: Identifiable {
    let id = UUID()
    var draft: JSONObject
    var title: String
    var creators: String
    var kind: String
    let confidence: String
    let remark: String
    var selected: Bool
    let dupTitle: String?
}

/// Add by photo.
/// - shelf: one or more shelf photos → Claude reads all spines → review list → add.
/// - cover: one front cover → (with key) recognise title → online details → form; own photo becomes the cover.
struct PhotoView: View {
    let mode: String
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var hint = ""
    @State private var rows: [PhotoRow] = []
    @State private var status = ""
    @State private var busy = false
    @State private var enrich = true
    @State private var room: String?
    @State private var camera = false
    @State private var library = false

    private var shelf: Bool { mode == "shelf" }
    private var hasKey: Bool { !model.settings.claudeKey.isEmpty }
    private var roomBinding: Binding<String> {
        Binding(get: { room ?? model.settings.lastRoom }, set: { room = $0.trimmed })
    }

    var body: some View {
        let selected = rows.filter(\.selected).count
        List {
            Section { intro }
            if !status.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(status)
                }
            }
            if !rows.isEmpty {
                Section {
                    Toggle(model.t("ai.enrich"), isOn: $enrich)
                    ForEach($rows) { $row in
                        RowEditor(row: $row)
                    }
                } header: {
                    HStack {
                        Text(model.t("ai.found", ["n": rows.count]))
                        Spacer()
                        Button(selected > 0 ? model.t("ai.none") : model.t("ai.all")) {
                            let on = selected == 0
                            for k in rows.indices { rows[k].selected = on }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(shelf ? model.t("add.shelf") : model.t("add.cover"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                Button {
                    Task { await addAll() }
                } label: {
                    Text(model.t("ai.addN", ["n": selected])).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || selected == 0)
                .padding(12)
                .background(.bar)
            }
        }
        .photoInput(camera: $camera, library: $library, maxCount: shelf ? nil : 1) { imgs in
            Task { await took(imgs) }
        }
    }

    @ViewBuilder
    private var intro: some View {
        if shelf && !hasKey {
            NoteBox { Text(model.t("ai.noKey")) }
        }
        if !shelf {
            Text(hasKey ? model.t("ai.coverHint") : model.t("ai.coverNoKey")).font(.caption).foregroundStyle(.secondary)
        }
        if shelf && hasKey {
            Text(model.t("ai.shelfHint")).font(.caption).foregroundStyle(.secondary)
        }
        SuggestField(label: model.t("field.room"), text: roomBinding, options: model.rooms)
        if hasKey {
            LabeledField(label: model.t("ai.hintPh"), text: $hint)
        }
        HStack(spacing: 10) {
            Button {
                camera = true
            } label: {
                Label(model.t("ai.camera"), systemImage: "camera").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                library = true
            } label: {
                Label(model.t("ai.gallery"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(busy || (shelf && !hasKey))
    }

    private func errorText(_ e: Error) -> String {
        if let e = e as? RecognizeError {
            return model.t("ai.err.\(e.code)") + (e.code == "other" || e.code == "parse" ? " (\(e.message))" : "")
        }
        return e.localizedDescription
    }

    private func recognize(_ jpeg: Data) async throws -> [Recognized] {
        let st = model.settings
        return try await Claude().recognizePhoto(apiKey: st.claudeKey, model: st.claudeModel, jpeg: jpeg, hint: hint)
    }

    private func took(_ images: [UIImage]) async {
        if !shelf {
            // one photo, large enough to read the title and small enough to keep as the cover
            if let img = images.first, let jpeg = ImageTools.jpeg(img, maxEdge: 1000, quality: 0.8) { await cover(jpeg) }
        } else {
            let photos = images.compactMap { ImageTools.jpeg($0, maxEdge: 2400, quality: 0.88) }
            if !photos.isEmpty { await readShelf(photos) }
        }
    }

    private func readShelf(_ photos: [Data]) async {
        busy = true
        for (n, photo) in photos.enumerated() {
            status = model.t("ai.reading", ["i": n + 1, "n": photos.count])
            do {
                for f in try await recognize(photo) {
                    let draft = f.toDraft()
                    let dup = findDuplicateOf(model.store.items, normalizeItem(draft))?.title
                        ?? rows.first(where: { $0.title == f.title && jStr($0.draft["volume"]) == f.volume.nonEmpty })?.title
                    rows.append(PhotoRow(draft: draft, title: f.title, creators: f.creators.joined(separator: ", "), kind: f.kind,
                                         confidence: f.confidence, remark: f.remark, selected: dup == nil, dupTitle: dup))
                }
            } catch {
                await model.dialogs.info(errorText(error))
                if (error as? RecognizeError)?.code == "auth" { break }
            }
        }
        busy = false
        status = ""
    }

    private func cover(_ photo: Data) async {
        let coverData = "data:image/jpeg;base64,\(photo.base64EncodedString())"
        let r = room ?? model.settings.lastRoom
        var draft: JSONObject = ["title": "", "coverData": coverData, "room": r.isEmpty ? NSNull() : r]
        if hasKey {
            busy = true
            status = model.t("ai.readingCover")
            do {
                if let first = try await recognize(photo).first {
                    draft.merge(first.toDraft()) { _, new in new }
                    draft["coverData"] = coverData
                    draft["source"] = "search"
                    status = model.t("ai.enriching")
                    let found = await Lookup.shared.searchOnline(first.kind, first.title, first.creators.first ?? "", googleKey: model.settings.googleBooksKey)
                    if let best = found.first(where: { matchScore(first.title, first.creators, $0) >= 0.75 }) {
                        draft.merge(enrichPatch(draft, best)) { _, new in new }
                        draft["needsCheck"] = false
                        draft.removeValue(forKey: "coverUrl")
                    }
                }
            } catch {
                await model.dialogs.info(errorText(error))
            }
        }
        busy = false
        status = ""
        // replace this screen with the form (only if the user is still here)
        if case .photo(_)? = router.path.last {
            router.path.removeLast()
            router.openForm(draft: draft)
        }
    }

    private func addAll() async {
        let sel = rows.filter(\.selected)
        let r0 = room ?? model.settings.lastRoom
        let key = model.settings.googleBooksKey
        busy = true
        var drafts: [JSONObject] = []
        for (n, row) in sel.enumerated() {
            var d = row.draft
            d["title"] = row.title.trimmed
            d["creators"] = row.creators.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
            d["kind"] = row.kind
            d["room"] = r0.isEmpty ? NSNull() : r0
            if enrich && (row.kind == "book" || row.kind == "cd") {
                status = model.t("ai.enrichingN", ["i": n + 1, "n": sel.count])
                let title = row.title.trimmed
                let creators = jStrList(d["creators"])
                let found = await Lookup.shared.searchOnline(row.kind, title, creators.first ?? "", googleKey: key)
                // keep the title as printed on the spine, only fill gaps
                if let best = found.first(where: { matchScore(title, creators, $0) >= 0.75 }) {
                    d.merge(enrichPatch(d, best)) { _, new in new }
                }
                // MusicBrainz asks for max. 1 request per second
                if row.kind == "cd" { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
            drafts.append(d)
        }
        model.store.addItems(drafts)
        model.updateSettings { $0.lastRoom = r0 }
        busy = false
        status = ""
        await model.dialogs.info(model.t("ai.added", ["n": drafts.count]))
        if case .photo(_)? = router.path.last { router.pop() }
    }
}

private struct RowEditor: View {
    @Binding var row: PhotoRow
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                row.selected.toggle()
            } label: {
                Image(systemName: row.selected ? "checkmark.square.fill" : "square").foregroundStyle(brandColor).imageScale(.large)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                TextField(model.t("field.title"), text: $row.title).fontWeight(.semibold)
                TextField(model.t("creator.\(row.kind)"), text: $row.creators)
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    Menu {
                        ForEach(kinds, id: \.self) { k in
                            Button("\(kindIcon[k] ?? "") \(model.t("kind.\(k)"))") { row.kind = k }
                        }
                    } label: {
                        Text("\(kindIcon[row.kind] ?? "") \(model.t("kind.\(row.kind)"))").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    let sv = [jStr(row.draft["series"]), jStr(row.draft["volume"])].compactMap { $0 }
                    if !sv.isEmpty { Text(sv.joined(separator: " ")).font(.caption) }
                    if row.confidence != "high" { Pill(model.t("ai.conf.\(row.confidence)"), color: amber.opacity(0.4)) }
                    if row.dupTitle != nil { Pill(model.t("ai.dup"), color: Color.pink.opacity(0.25)) }
                }
                if !row.remark.isEmpty { Text(row.remark).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .opacity(row.selected ? 1 : 0.5)
    }
}
