import SwiftUI
import MybibCore

@MainActor
func shareText(_ item: Item, _ model: AppModel) -> String {
    var lines = [item.title + (item.creators.isEmpty ? "" : " – \(item.creators.joined(separator: ", "))")]
    if item.rating > 0 { lines.append(String(repeating: "★", count: item.rating) + String(repeating: "☆", count: 5 - item.rating)) }
    if let n = item.notes { lines.append(n) }
    if item.recommend { lines.append(model.t("share.recommend")) }
    var text = lines.joined(separator: "\n")
    if let isbn = item.isbn {
        if item.kind == "book" { text += "\nhttps://openlibrary.org/isbn/\(isbn)" }
        if item.kind == "cd" { text += "\nhttps://musicbrainz.org/search?type=release&query=barcode:\(isbn)" }
    }
    return text
}

struct ItemDetailView: View {
    let id: String
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        if let item = model.store.byId(id) {
            ItemDetailContent(item: item)
        } else {
            Color.clear
        }
    }
}

private struct ItemDetailContent: View {
    let item: Item
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var notes = ""
    @State private var room = ""
    @State private var lending = false
    @State private var lendTo = ""
    @State private var moreInfo = false
    @State private var camera = false
    @State private var library = false
    @State private var searching = false

    private func up(_ p: JSONObject) { model.store.updateItem(item.id, p) }

    private func fmtDate(_ d: String) -> String {
        let p = d.split(separator: "-").map { String($0) }
        guard p.count == 3, model.lang == "de", let day = Int(p[2]), let month = Int(p[1]) else { return d }
        return "\(day).\(month).\(p[0])"
    }

    var body: some View {
        Form {
            Section { header }
            if item.needsCheck {
                Section {
                    NoteBox {
                        Text(model.t("detail.needsCheck"))
                        HStack(spacing: 16) {
                            Button("✓ \(model.t("detail.checked"))") { up(["needsCheck": false]) }
                            Button("🔎 \(model.t("detail.enrich"))") { searching = true }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listRowInsets(EdgeInsets())
            }
            Section(model.t("detail.status")) { statusFields }
            if item.owned && item.format == "physical" {
                Section(model.t("detail.place")) {
                    SuggestField(label: model.t("field.room"), text: $room, options: model.rooms)
                }
                Section(model.t("detail.loan")) { loanFields }
            }
            Section(model.t("field.notes")) {
                TextField(model.t("detail.notesPh"), text: $notes, axis: .vertical).lineLimit(2...10)
            }
            Section { facts }
        }
        .navigationTitle("\(kindIcon[item.kind] ?? "") \(model.t("kind.\(item.kind)"))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText(item, model), subject: Text(item.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(model.t("detail.share"))
                Button {
                    router.openForm(id: item.id)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(model.t("detail.edit"))
                Button {
                    Task { await delete() }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(model.t("detail.delete"))
            }
        }
        .onAppear {
            // (re)load after editing in the form
            notes = item.notes ?? ""
            room = item.room ?? ""
        }
        .onChange(of: notes) { _, v in
            if jStr(v) != item.notes { up(["notes": v]) }
        }
        .onChange(of: room) { _, v in
            let r = v.trimmed
            if r.nonEmpty != item.room { up(["room": r.isEmpty ? NSNull() : r]) }
        }
        .photoInput(camera: $camera, library: $library) { imgs in
            if let img = imgs.first, let data = ImageTools.coverDataURL(img) { up(["coverData": data]) }
        }
        .sheet(isPresented: $searching) {
            SearchSheet(kind: item.kind, title: item.title, creator: item.creators.first ?? "") { c in
                var p = enrichPatch(item.toJSON(), c)
                p["needsCheck"] = false
                up(p)
            }
            .environment(model)
        }
    }

    private func delete() async {
        guard await model.dialogs.confirm(model.t("detail.deleteConfirm", ["title": item.title])) else { return }
        let id = item.id
        router.pop()
        model.store.removeItems([id])
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Menu {
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
                if item.coverData != nil {
                    Button(item.coverUrl != nil ? model.t("cover.useOnline") : model.t("form.coverRemove"), role: .destructive) {
                        up(["coverData": NSNull()])
                    }
                }
            } label: {
                CoverImage(item: item, large: true)
                    .overlay(alignment: .bottomTrailing) {
                        Text("📷").font(.system(size: 14)).padding(5).background(Circle().fill(.background)).offset(x: 6, y: 6)
                    }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.t("cover.change"))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.title3).fontWeight(.semibold)
                if let s = item.subtitle { Text(s).foregroundStyle(.secondary) }
                if !item.creators.isEmpty { Text(item.creators.joined(separator: ", ")).fontWeight(.semibold) }
                Stars(value: item.rating) { r in up(["rating": r]) }.padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusFields: some View {
        Picker(model.t("detail.status"), selection: Binding(get: { item.status }, set: { up(["status": $0]) })) {
            ForEach(statuses, id: \.self) { st in
                Text(model.t("status.\(item.kind).\(st)")).tag(st)
            }
        }
        .pickerStyle(.segmented)
        CategoryMenu(value: item.category ?? "") { v in up(["category": v.isEmpty ? NSNull() : v]) }
        Toggle(model.t("detail.wishlist"), isOn: Binding(get: { !item.owned }, set: { up(["owned": !$0]) }))
        Toggle("👍 \(model.t("detail.recommend"))", isOn: Binding(get: { item.recommend }, set: { up(["recommend": $0]) }))
        if item.kind == "book" {
            OptionPicker(label: model.t("field.format"), value: item.format, options: formats.map { Choice($0, model.t("format.\($0)")) }) { up(["format": $0]) }
        }
    }

    @ViewBuilder
    private var loanFields: some View {
        if let loan = item.openLoan {
            HStack {
                Text(model.t("detail.lentTo", ["name": loan.to, "date": fmtDate(loan.since)]))
                Spacer()
                Button("↩ \(model.t("detail.returned"))") {
                    let loans = item.loans.map { $0 == loan ? Loan(to: $0.to, since: $0.since, returned: today()) : $0 }
                    up(["loans": loans])
                }
                .buttonStyle(.bordered)
            }
        } else if lending {
            HStack {
                SuggestField(label: model.t("detail.lendWho"), text: $lendTo, options: knownPeople(model.store.items))
                Button(model.t("ok")) {
                    let to = lendTo.trimmed
                    guard !to.isEmpty else { return }
                    up(["loans": item.loans + [Loan(to: to, since: today())]])
                    lending = false
                    lendTo = ""
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button("↗ \(model.t("detail.lend"))") { lending = true }
        }
        ForEach(Array(item.loans.filter { $0.returned != nil }.enumerated()), id: \.offset) { _, l in
            Text(model.t("detail.loanPast", ["name": l.to, "from": fmtDate(l.since), "to": fmtDate(l.returned ?? "")]))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var factList: [(String, String)] {
        var out: [(String, String)] = []
        func add(_ key: String, _ v: String?) {
            if let v, !v.isEmpty { out.append((model.t(key), v)) }
        }
        add("field.series", [item.series, item.volume].compactMap { $0 }.joined(separator: " · "))
        add("field.publisher", item.publisher)
        add("field.year", item.year.map { String($0) })
        add("field.pages", item.pages.map { String($0) })
        add("field.language", item.language)
        add("field.isbn", item.isbn)
        if let lo = item.playersMin {
            let hi: String = item.playersMax.flatMap { $0 != lo ? "–\($0)" : nil } ?? ""
            add("field.players", "\(lo)\(hi)")
        }
        add("field.playMinutes", item.playMinutes.map { String($0) })
        add("field.ageFrom", item.ageFrom.map { "\($0)+" })
        add("field.tags", item.tags.joined(separator: ", "))
        return out
    }

    @ViewBuilder
    private var facts: some View {
        let list = factList
        if !list.isEmpty {
            FlowLayout(spacing: 24, lineSpacing: 10) {
                ForEach(list.indices, id: \.self) { n in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(list[n].0).font(.caption2).foregroundStyle(.secondary)
                        Text(list[n].1).textSelection(.enabled)
                    }
                }
            }
        }
        if let d = item.description {
            Text(d).lineLimit(moreInfo ? nil : 4)
            Button(moreInfo ? model.t("less") : model.t("more")) { moreInfo.toggle() }.buttonStyle(.borderless)
        }
        if !item.needsCheck && (!item.hasCover || item.publisher == nil) {
            Button("🔎 \(model.t("detail.enrich"))") { searching = true }.buttonStyle(.borderless)
        }
    }
}
