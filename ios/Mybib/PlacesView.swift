import SwiftUI
import MybibCore

struct PlacesView: View {
    @Environment(AppModel.self) private var model

    private var configured: [String] {
        model.settings.rooms.isEmpty ? defaultRooms.map { model.lang == "de" ? $0[0] : $0[1] } : model.settings.rooms
    }

    private var byRoom: [String: Int] {
        var m: [String: Int] = [:]
        for p in summarizePlaces(model.store.items) { m[p.room] = p.count }
        return m
    }

    private func saveRooms(_ list: [String]) {
        var seen = Set<String>()
        let clean = list.filter { !$0.isEmpty && seen.insert($0).inserted }
        model.updateSettings { $0.rooms = clean }
    }

    var body: some View {
        let counts = byRoom
        List {
            Section { StatsGrid() }
            CategoryChips()
            Section {
                ForEach(model.rooms, id: \.self) { room in
                    HStack {
                        Button {
                            model.showInLibrary(Filters(scope: "owned", format: "physical", room: room), sortBy: "place")
                        } label: {
                            HStack {
                                Text("🏠").font(.title3)
                                VStack(alignment: .leading) {
                                    Text(room).foregroundStyle(Color.primary)
                                    Text("\(counts[room] ?? 0)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        Button {
                            Task { await rename(room) }
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.t("places.rename"))
                        Button {
                            Task { await remove(room, count: counts[room] ?? 0) }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.t("places.remove"))
                    }
                }
                if let n = counts[""], n > 0 {
                    Button {
                        model.showInLibrary(Filters(scope: "owned", format: "physical", room: ""))
                    } label: {
                        HStack {
                            Text("❔").font(.title3)
                            VStack(alignment: .leading) {
                                Text(model.t("places.none")).foregroundStyle(Color.primary)
                                Text("\(n)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    Task { await addRoom() }
                } label: {
                    Label(model.t("places.addRoom"), systemImage: "plus")
                }
            } header: {
                Text(model.t("nav.places"))
            } footer: {
                Text(model.t("places.tip"))
            }
        }
        .navigationTitle(model.t("nav.places"))
    }

    private func addRoom() async {
        guard let name = await model.dialogs.prompt(model.t("places.newRoom"))?.trimmed, !name.isEmpty, !model.rooms.contains(name) else { return }
        saveRooms(configured + [name])
    }

    private func rename(_ room: String) async {
        guard let name = await model.dialogs.prompt(model.t("places.renameRoom", ["room": room]), initial: room)?.trimmed,
              !name.isEmpty, name != room else { return }
        if model.rooms.contains(name) {
            let ok = await model.dialogs.confirm(model.t("places.mergeConfirm", ["room": room, "name": name]))
            if !ok { return }
        }
        let conf = configured
        model.store.moveRoom(room, name)
        saveRooms(conf.contains(room) ? conf.map { $0 == room ? name : $0 } : conf)
    }

    private func remove(_ room: String, count n: Int) async {
        if n > 0 {
            let ok = await model.dialogs.confirm(model.t("places.removeRoomConfirm", ["room": room, "n": n]))
            if !ok { return }
            model.store.moveRoom(room, "")
        }
        saveRooms(configured.filter { $0 != room })
    }
}

private struct StatsGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.store.items
        let owned = items.filter(\.owned)
        var stats: [(String, Int)] = kinds.map { k in (model.t("kind.\(k).pl"), owned.filter { $0.kind == k }.count) }
        stats += [
            (model.t("places.digital"), owned.filter { $0.format != "physical" }.count),
            (model.t("places.done"), items.filter { $0.status == "done" }.count),
            (model.t("places.want"), items.filter { $0.status == "want" }.count),
            (model.t("scope.lent"), items.filter { $0.openLoan != nil }.count),
            (model.t("scope.wish"), items.count - owned.count),
        ]
        let shown = stats.filter { $0.1 > 0 }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(shown.indices, id: \.self) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shown[n].1)").font(.title2).fontWeight(.bold)
                    Text(shown[n].0).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
            }
        }
    }
}

private struct CategoryChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.store.items
        var count: [String: Int] = [:]
        for i in items { count[i.category ?? "", default: 0] += 1 }
        let cats = (model.store.categories() + [""]).filter { (count[$0] ?? 0) > 0 }
        let show = !cats.isEmpty && !(cats.count == 1 && cats[0].isEmpty)
        return Group {
            if show {
                Section(model.t("field.category")) {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(cats, id: \.self) { c in
                            Chip(label: "\(c.isEmpty ? model.t("cat.none") : model.catLabel(c))  \(count[c] ?? 0)", on: false) {
                                model.showInLibrary(Filters(category: c))
                            }
                        }
                    }
                }
            }
        }
    }
}
