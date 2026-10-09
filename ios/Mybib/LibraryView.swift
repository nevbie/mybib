import SwiftUI
import MybibCore

struct IdList: Identifiable {
    let id = UUID()
    let ids: [String]
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var more = false
    /// bulk edit: nil = normal mode, otherwise the selected ids
    @State private var selection: Set<String>?
    @State private var bulkEdit: IdList?

    var body: some View {
        let items = model.store.items
        let list = sortItems(applyFilters(items, model.filters), model.sort)
        List {
            Section {
                chips(items)
                if more { FilterPanel() }
                statusRow(items: items, list: list)
            }
            .listRowSeparator(.hidden)
            Section {
                ForEach(list) { item in
                    ItemRow(item: item, selected: selection.map { $0.contains(item.id) })
                        .contentShape(Rectangle())
                        .onTapGesture { tap(item) }
                        .onLongPressGesture {
                            if selection == nil { selection = [item.id] }
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("mybib")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(items.count)").foregroundStyle(.secondary)
            }
        }
        .searchable(text: Binding(get: { model.filters.q }, set: { model.filters.q = $0 }), prompt: model.t("lib.search"))
        .sheet(item: $bulkEdit) { b in
            BulkEditSheet(ids: b.ids).environment(model)
        }
    }

    private func tap(_ item: Item) {
        if selection != nil {
            if selection?.contains(item.id) == true {
                selection?.remove(item.id)
            } else {
                selection?.insert(item.id)
            }
        } else {
            router.push(.item(item.id))
        }
    }

    private func setFilters(_ change: (inout Filters) -> Void) {
        var f = model.filters
        change(&f)
        model.filters = f
    }

    @ViewBuilder
    private func chips(_ items: [Item]) -> some View {
        let f = model.filters
        let counts: [String: Int] = [
            "wish": items.filter { !$0.owned }.count,
            "lent": items.filter { $0.openLoan != nil }.count,
            "recommend": items.filter(\.recommend).count,
            "check": items.filter(\.needsCheck).count,
        ]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: model.t("kind.all"), on: f.kind == "all") { setFilters { $0.kind = "all" } }
                ForEach(kinds, id: \.self) { k in
                    Chip(label: model.t("kind.\(k).pl"), on: f.kind == k) { setFilters { $0.kind = f.kind == k ? "all" : k } }
                }
            }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: model.t("scope.all"), on: f.scope == "all") { setFilters { $0.scope = "all" } }
                ForEach(["wish", "lent", "recommend", "check"], id: \.self) { sc in
                    let n = counts[sc] ?? 0
                    if n > 0 || f.scope == sc {
                        Chip(label: "\(model.t("scope.\(sc)"))  \(n)", on: f.scope == sc) { setFilters { $0.scope = f.scope == sc ? "all" : sc } }
                    }
                }
                let extra = f.extraActive
                Chip(label: "⚙︎ \(model.t("lib.more"))" + (extra > 0 ? "  \(extra)" : ""), on: more || extra > 0) { more.toggle() }
            }
        }
    }

    @ViewBuilder
    private func statusRow(items: [Item], list: [Item]) -> some View {
        if model.store.ready && items.isEmpty {
            VStack(spacing: 16) {
                Text(model.t("lib.empty")).multilineTextAlignment(.center)
                Button {
                    model.tab = 1
                } label: {
                    Label(model.t("nav.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else if let sel = selection {
            let selected = list.filter { sel.contains($0.id) }.map(\.id)
            HStack {
                Text(model.t("sel.count", ["n": selected.count])).fontWeight(.semibold)
                Spacer()
                Button(selected.count == list.count ? model.t("ai.none") : model.t("sel.all", ["n": list.count])) {
                    selection = selected.count == list.count ? [] : Set(list.map(\.id))
                }
                .buttonStyle(.borderless)
                Button {
                    bulkEdit = IdList(ids: selected)
                } label: {
                    Label(model.t("sel.edit"), systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(brandColor.opacity(0.12)))
        } else {
            HStack {
                Text(list.count != items.count ? model.t("lib.shown", ["n": list.count]) : "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !list.isEmpty {
                    Button {
                        selection = []
                    } label: {
                        Label(model.t("sel.start"), systemImage: "checklist")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !items.isEmpty && list.isEmpty {
                Text(model.t("lib.noMatch")).frame(maxWidth: .infinity).padding(24)
            }
        }
    }
}

/// Status, format, category, room, rating and sort.
private struct FilterPanel: View {
    @Environment(AppModel.self) private var model

    private func set(_ change: (inout Filters) -> Void) {
        var f = model.filters
        change(&f)
        model.filters = f
    }

    var body: some View {
        let f = model.filters
        let any = model.t("any")
        let rooms = model.rooms
        let statusKind = f.kind == "all" ? "book" : f.kind
        let roomValue = rooms.contains(f.room) || f.room == "all" || f.room == "" ? f.room : "all"
        let statusOpts: [Choice<String>] = [Choice("all", any)] + statuses.map { Choice($0, model.t("status.\(statusKind).\($0)")) }
        let formatOpts: [Choice<String>] = [Choice("all", any)] + formats.map { Choice($0, model.t("format.\($0)")) }
        let roomOpts: [Choice<String>] = [Choice("all", any)] + rooms.map { Choice($0, $0) } + [Choice("", model.t("places.none"))]
        let ratingOpts: [Choice<Int>] = [Choice(0, any)] + (1...5).map { Choice($0, String(repeating: "★", count: $0)) }
        let sortOpts: [Choice<String>] = sortKeys.map { Choice($0, model.t("sort.\($0)")) }
        VStack(spacing: 4) {
            OptionPicker(label: model.t("lib.status"), value: f.status, options: statusOpts) { v in set { $0.status = v } }
            OptionPicker(label: model.t("field.format"), value: f.format, options: formatOpts) { v in set { $0.format = v } }
            CategoryMenu(value: f.category, extra: [Choice("all", any)]) { v in set { $0.category = v } }
            OptionPicker(label: model.t("field.room"), value: roomValue, options: roomOpts) { v in set { $0.room = v } }
            OptionPicker(label: model.t("lib.minRating"), value: f.minRating, options: ratingOpts) { v in set { $0.minRating = v } }
            OptionPicker(label: model.t("lib.sort"), value: model.sort, options: sortOpts) { v in model.sort = v }
            HStack {
                Spacer()
                Button(model.t("lib.reset")) { model.filters = Filters() }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
    }
}
