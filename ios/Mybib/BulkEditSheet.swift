import SwiftUI
import MybibCore

private let unchanged = "\u{0}unchanged"
private let noneValue = "\u{0}none"
private let newValue = "\u{0}new"

/// Change room, category, status, rating, kind, format, wishlist, recommendation or tags of
/// many items at once. Only what is changed here is applied.
struct BulkEditSheet: View {
    let ids: [String]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dialogs = DialogCenter()
    @State private var room = unchanged
    @State private var category = unchanged
    @State private var status = unchanged
    @State private var kind = unchanged
    @State private var format = unchanged
    @State private var owned = unchanged
    @State private var recommend = unchanged
    @State private var rating = unchanged
    @State private var removeTag = ""
    @State private var newRoom = ""
    @State private var addTag = ""
    @State private var checked = false

    private var live: [String] { ids.filter { model.store.byId($0) != nil } }

    private var changes: Int {
        [
            room != unchanged && (room != newValue || !newRoom.trimmed.isEmpty),
            category != unchanged, status != unchanged, kind != unchanged, format != unchanged,
            owned != unchanged, recommend != unchanged, rating != unchanged,
            !addTag.trimmed.isEmpty, !removeTag.isEmpty, checked,
        ].filter { $0 }.count
    }

    var body: some View {
        let n = live.count
        NavigationStack {
            Form {
                Section {
                    Text(model.t("bulkEdit.intro")).font(.caption).foregroundStyle(.secondary)
                    placeFields
                }
                Section { valueFields }
                Section { tagFields }
                Section {
                    Button {
                        apply()
                    } label: {
                        Text(model.t("bulkEdit.apply", ["n": n])).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(changes == 0 || n == 0)
                    Button(role: .destructive) {
                        Task { await delete() }
                    } label: {
                        Label(model.t("detail.delete"), systemImage: "trash")
                    }
                    .disabled(n == 0)
                }
            }
            .navigationTitle(model.t("bulkEdit.title", ["n": n]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.t("close")) { dismiss() }
                }
            }
        }
        .modifier(DialogHost(center: dialogs, ok: model.t("ok"), cancel: model.cancelText))
    }

    private var labelKind: String {
        let used = Set(live.compactMap { model.store.byId($0)?.kind })
        return used.count == 1 ? (used.first ?? "book") : "book"
    }

    @ViewBuilder
    private var placeFields: some View {
        let un = Choice(unchanged, model.t("bulkEdit.unchanged"))
        let roomOpts: [Choice<String>] = [un] + model.rooms.map { Choice($0, $0) }
            + [Choice(noneValue, model.t("places.none")), Choice(newValue, model.t("bulkEdit.newRoom"))]
        OptionPicker(label: model.t("field.room"), value: room, options: roomOpts) { room = $0 }
        if room == newValue {
            LabeledField(label: model.t("places.newRoom"), text: $newRoom)
        }
        CategoryMenu(value: category, extra: [un], noneValue: noneValue) { category = $0 }
    }

    @ViewBuilder
    private var valueFields: some View {
        let un = Choice(unchanged, model.t("bulkEdit.unchanged"))
        let statusOpts: [Choice<String>] = [un] + statuses.map { st in
            Choice(st, st == "none" ? model.t("bulkEdit.noStatus") : model.t("status.\(labelKind).\(st)"))
        }
        let ratingOpts: [Choice<String>] = [un, Choice("0", model.t("bulkEdit.noRating"))]
            + (1...5).map { Choice(String($0), String(repeating: "★", count: $0)) }
        let kindOpts: [Choice<String>] = [un] + kinds.map { Choice($0, model.t("kind.\($0)")) }
        let formatOpts: [Choice<String>] = [un] + formats.map { Choice($0, model.t("format.\($0)")) }
        let ownedOpts: [Choice<String>] = [un, Choice("yes", model.t("bulkEdit.owned")), Choice("no", model.t("scope.wish"))]
        let recOpts: [Choice<String>] = [un, Choice("yes", model.t("bulkEdit.yes")), Choice("no", model.t("bulkEdit.no"))]
        OptionPicker(label: model.t("detail.status"), value: status, options: statusOpts) { status = $0 }
        OptionPicker(label: model.t("rating"), value: rating, options: ratingOpts) { rating = $0 }
        OptionPicker(label: model.t("field.kind"), value: kind, options: kindOpts) { kind = $0 }
        OptionPicker(label: model.t("field.format"), value: format, options: formatOpts) { format = $0 }
        OptionPicker(label: model.t("scope.wish"), value: owned, options: ownedOpts) { owned = $0 }
        OptionPicker(label: "👍 \(model.t("detail.recommend"))", value: recommend, options: recOpts) { recommend = $0 }
    }

    @ViewBuilder
    private var tagFields: some View {
        let items = live.compactMap { model.store.byId($0) }
        let allTags = Array(Set(items.flatMap(\.tags))).sorted()
        LabeledField(label: model.t("bulkEdit.addTag"), text: $addTag, hint: model.t("form.tagsHint"))
        if !allTags.isEmpty {
            let tagOpts: [Choice<String>] = [Choice("", "–")] + allTags.map { Choice($0, $0) }
            OptionPicker(label: model.t("bulkEdit.removeTag"), value: removeTag, options: tagOpts) { removeTag = $0 }
        }
        Toggle(model.t("bulkEdit.checked"), isOn: $checked)
    }

    private func apply() {
        var patch = JSONObject()
        if room != unchanged {
            let r = room == newValue ? newRoom.trimmed : (room == noneValue ? "" : room)
            if room != newValue || !r.isEmpty { patch["room"] = r.isEmpty ? NSNull() : r }
        }
        if category != unchanged { patch["category"] = category == noneValue ? NSNull() : category }
        if status != unchanged { patch["status"] = status }
        if kind != unchanged { patch["kind"] = kind }
        if format != unchanged { patch["format"] = format }
        if owned != unchanged { patch["owned"] = owned == "yes" }
        if recommend != unchanged { patch["recommend"] = recommend == "yes" }
        if rating != unchanged { patch["rating"] = Int(rating) ?? 0 }
        if checked { patch["needsCheck"] = false }
        let tag = addTag.trimmed
        let remove = removeTag
        model.store.updateItems(live) { i in
            var p = patch
            if !tag.isEmpty || !remove.isEmpty {
                var tags = i.tags.filter { $0 != remove }
                if !tag.isEmpty, !tags.contains(tag) { tags.append(tag) }
                p["tags"] = tags
            }
            return p
        }
        dismiss()
    }

    private func delete() async {
        let ids = live
        guard await dialogs.confirm(model.t("bulkEdit.deleteConfirm", ["n": ids.count])) else { return }
        model.store.removeItems(ids)
        dismiss()
    }
}
