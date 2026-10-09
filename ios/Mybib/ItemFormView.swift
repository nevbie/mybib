import SwiftUI
import MybibCore

private let textFields = ["title", "subtitle", "series", "volume", "publisher", "year", "isbn", "language", "pages", "ageFrom",
                          "playersMin", "playersMax", "playMinutes", "room", "notes"]

private func splitList(_ v: String) -> [String] {
    v.split(whereSeparator: { $0 == "," || $0 == ";" }).map { String($0).trimmed }.filter { !$0.isEmpty }
}

/// New entry (optionally prefilled from a draft) or edit an existing one.
struct ItemFormView: View {
    let request: FormRequest
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    /// non-text fields (kind, format, owned, status, category, covers, source …)
    @State private var d: JSONObject = [:]
    @State private var text: [String: String] = [:]
    @State private var creators = ""
    @State private var tags = ""
    @State private var loaded = false
    @State private var camera = false
    @State private var library = false
    @State private var searching = false

    private var kind: String { d["kind"] as? String ?? "book" }
    private var isNew: Bool { request.id == nil }

    private func field(_ k: String) -> Binding<String> {
        Binding(get: { text[k] ?? "" }, set: { text[k] = $0 })
    }

    private func load(_ m: JSONObject) {
        d = m
        var t: [String: String] = [:]
        for k in textFields { t[k] = jStr(m[k]) ?? "" }
        text = t
        creators = jStrList(m["creators"]).joined(separator: ", ")
        tags = jStrList(m["tags"]).joined(separator: ", ")
    }

    private func full() -> JSONObject {
        var v = d
        for k in textFields {
            let s = (text[k] ?? "").trimmed
            v[k] = s.isEmpty ? NSNull() : s
        }
        v["creators"] = splitList(creators)
        v["tags"] = splitList(tags)
        return v
    }

    var body: some View {
        let title = (text["title"] ?? "").trimmed
        let dup = isNew && !title.isEmpty ? findDuplicateOf(model.store.items, normalizeItem(full())) : nil
        Form {
            Section {
                Picker(model.t("field.kind"), selection: Binding(get: { kind }, set: setKind)) {
                    ForEach(kinds, id: \.self) { Text(model.t("kind.\($0)")).tag($0) }
                }
                .pickerStyle(.segmented)
                CategoryMenu(value: d["category"] as? String ?? "") { v in d["category"] = v.isEmpty ? NSNull() : v }
            }
            Section { coverRow }
            Section {
                LabeledField(label: "\(model.t("field.title")) *", text: field("title"))
                if let dup {
                    Button("⚠︎ \(model.t("form.duplicate")) \(dup.title)") { router.push(.item(dup.id)) }
                        .foregroundStyle(.orange)
                        .buttonStyle(.borderless)
                }
                LabeledField(label: model.t("creator.\(kind)"), text: $creators, hint: model.t("form.commaHint"))
                if kind == "book" { LabeledField(label: model.t("field.subtitle"), text: field("subtitle")) }
                detailFields
            }
            Section { stateFields }
            Section {
                Button {
                    save()
                } label: {
                    Text(model.t("save")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .navigationTitle(isNew ? model.t("form.new") : model.t("form.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.t("save")) { save() }.disabled(title.isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = request.id, let existing = model.store.byId(id) {
                load(existing.toJSON())
            } else {
                var m: JSONObject = ["kind": "book", "format": "physical", "owned": true, "status": "none"]
                if !model.settings.lastRoom.isEmpty { m["room"] = model.settings.lastRoom }
                m.merge(request.draft ?? [:]) { _, new in new }
                load(m)
            }
        }
        .photoInput(camera: $camera, library: $library) { imgs in
            if let img = imgs.first, let data = ImageTools.coverDataURL(img) { d["coverData"] = data }
        }
        .sheet(isPresented: $searching) {
            SearchSheet(kind: kind, title: text["title"] ?? "", creator: splitList(creators).first ?? "", onPick: fillOnline)
                .environment(model)
        }
    }

    private func setKind(_ k: String) {
        d["kind"] = k
        if k != "book" { d["format"] = "physical" }
    }

    private var coverRow: some View {
        HStack(alignment: .top, spacing: 14) {
            let t = text["title"] ?? ""
            CoverImage(title: t.isEmpty ? "?" : t, kind: kind, coverUrl: jStr(d["coverUrl"]), coverData: jStr(d["coverData"]), large: true)
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    camera = true
                } label: {
                    Label(model.t("cover.camera"), systemImage: "camera")
                }
                Button {
                    library = true
                } label: {
                    Label(model.t("cover.gallery"), systemImage: "photo.on.rectangle")
                }
                if jStr(d["coverData"]) != nil || jStr(d["coverUrl"]) != nil {
                    Button(model.t("form.coverRemove"), role: .destructive) {
                        d.removeValue(forKey: "coverData")
                        d.removeValue(forKey: "coverUrl")
                    }
                }
                Button {
                    searching = true
                } label: {
                    Label(model.t("form.fillOnline"), systemImage: "magnifyingglass")
                }
                .disabled(kind == "game")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var detailFields: some View {
        let isBook = kind == "book"
        HStack {
            LabeledField(label: model.t("field.seriesOnly"), text: field("series"))
            LabeledField(label: model.t("field.volume"), text: field("volume"))
        }
        HStack {
            LabeledField(label: model.t(kind == "cd" ? "field.label" : "field.publisher"), text: field("publisher"))
            LabeledField(label: model.t("field.year"), text: field("year"), keyboard: .numberPad)
        }
        HStack {
            LabeledField(label: model.t(isBook ? "field.isbn" : "field.ean"), text: field("isbn"), keyboard: .numbersAndPunctuation)
            LabeledField(label: model.t("field.language"), text: field("language"), hint: "de, en, zh …")
        }
        HStack {
            if isBook { LabeledField(label: model.t("field.pages"), text: field("pages"), keyboard: .numberPad) }
            LabeledField(label: model.t("field.ageFrom"), text: field("ageFrom"), keyboard: .numberPad)
        }
        if kind == "game" {
            HStack {
                LabeledField(label: model.t("field.playersMin"), text: field("playersMin"), keyboard: .numberPad)
                LabeledField(label: model.t("field.playersMax"), text: field("playersMax"), keyboard: .numberPad)
            }
            LabeledField(label: model.t("field.playMinutes"), text: field("playMinutes"), keyboard: .numberPad)
        }
    }

    @ViewBuilder
    private var stateFields: some View {
        let owned = jBool(d["owned"]) != false
        let format = d["format"] as? String ?? "physical"
        if kind == "book" {
            Picker(model.t("field.format"), selection: Binding(get: { format }, set: { d["format"] = $0 })) {
                ForEach(formats, id: \.self) { Text(model.t("format.\($0)")).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        OptionPicker(label: model.t("detail.status"), value: d["status"] as? String ?? "none",
                     options: statuses.map { Choice($0, model.t("status.\(kind).\($0)")) }) { d["status"] = $0 }
        Toggle(model.t("detail.wishlist"), isOn: Binding(get: { !owned }, set: { d["owned"] = !$0 }))
        if owned && format == "physical" {
            SuggestField(label: model.t("field.room"), text: field("room"), options: model.rooms)
        }
        LabeledField(label: model.t("field.tags"), text: $tags, hint: model.t("form.tagsHint"))
        VStack(alignment: .leading, spacing: 2) {
            Text(model.t("field.notes")).font(.caption).foregroundStyle(.secondary)
            TextField("", text: field("notes"), axis: .vertical).lineLimit(2...10)
        }
    }

    private func fillOnline(_ c: Candidate) {
        let cur = full()
        let patch = (text["title"] ?? "").trimmed.isEmpty ? c.data : enrichPatch(cur, c)
        var m = cur.merging(patch) { _, new in new }
        m["kind"] = kind
        let source: Any = isNew ? "search" : (d["source"] ?? NSNull())
        m["source"] = source
        load(m)
    }

    private func save() {
        var v = full()
        guard let title = v["title"] as? String, !title.isEmpty else { return }
        if let s = v["isbn"] as? String, let code = classifyCode(s) { v["isbn"] = code.code }
        if let id = request.id {
            model.store.updateItem(id, v)
        } else {
            model.store.addItems([v])
            let room = v["room"] as? String ?? ""
            model.updateSettings { $0.lastRoom = room }
        }
        router.pop()
    }
}
