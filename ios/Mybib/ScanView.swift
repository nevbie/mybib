import SwiftUI
import UIKit
import MybibCore

/// Barcode scanning: add to shelf, add to wishlist, or just check "do I own this?".
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var mode = "own"
    /// scan / busy / found / none
    @State private var phase = "scan"
    @State private var code = ""
    @State private var found: [Candidate] = []
    @State private var dup: Item?
    @State private var added: [Item] = []
    /// nil = the last used room
    @State private var room: String?
    @State private var last = ""
    @State private var manual = ""
    @State private var cameraFailed = false

    private var roomBinding: Binding<String> {
        Binding(get: { room ?? model.settings.lastRoom }, set: { room = $0.trimmed })
    }

    var body: some View {
        let showResult = phase == "found" || phase == "none"
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker(model.t("scan.mode"), selection: $mode) {
                    ForEach(["own", "wish", "check"], id: \.self) { Text(model.t("scan.mode.\($0)")).tag($0) }
                }
                .pickerStyle(.segmented)
                if mode == "own" {
                    SuggestField(label: model.t("field.room"), text: roomBinding, options: model.rooms)
                }
                camera
                HStack {
                    TextField(model.t("scan.manual"), text: $manual)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { handle(manual) }
                    Button(model.t("ok")) { handle(manual) }.buttonStyle(.borderedProminent)
                }
                if phase == "busy" {
                    HStack {
                        ProgressView()
                        Text(model.t("scan.looking", ["code": code]))
                    }
                }
                if showResult { results }
                if !added.isEmpty {
                    Text(model.t("scan.added", ["n": added.count])).fontWeight(.bold).padding(.top, 8)
                    ForEach(added) { i in Text("• \(i.title)") }
                }
            }
            .padding(16)
        }
        .navigationTitle(model.t("scan.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var camera: some View {
        ZStack {
            if cameraFailed {
                Color.black
                Text(model.t("scan.unsupported")).foregroundStyle(.white).multilineTextAlignment(.center).padding()
            } else {
                BarcodeScanner(onCode: detected, onFail: { cameraFailed = true })
                Rectangle().fill(Color.red.opacity(0.8)).frame(height: 2).padding(.horizontal, 40)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var results: some View {
        if let dup {
            NoteBox {
                Text("\(mode == "check" ? "✅ " : "⚠︎ ")\(model.t("scan.have", ["title": dup.title, "place": dup.room ?? "–"]))")
                Button(model.t("scan.open")) { router.push(.item(dup.id)) }.buttonStyle(.borderless)
            }
        } else if mode == "check" {
            NoteBox(color: Color.secondary.opacity(0.12)) { Text("❌ \(model.t("scan.notHave"))") }
        }
        if phase == "found" {
            ForEach(Array(found.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 8) {
                    CandidateRow(candidate: c, large: true)
                    if mode != "check" {
                        HStack {
                            Button("＋ \(mode == "wish" ? model.t("scan.addWish") : model.t("scan.add"))") { add(c) }
                                .buttonStyle(.borderedProminent)
                            Button(model.t("scan.edit")) { edit(c.data) }.buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
            }
        }
        if phase == "none" {
            NoteBox(color: Color.secondary.opacity(0.12)) {
                Text(model.t("scan.notFound", ["code": code]))
                if mode != "check" {
                    Button(model.t("scan.manualAdd")) {
                        edit(["title": "", "isbn": code, "kind": code.hasPrefix("97") ? "book" : "dvd"])
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        Button(model.t("scan.next")) { phase = "scan" }
    }

    private func detected(_ v: String) {
        guard phase == "scan", classifyCode(v) != nil else { return }
        // need the same reading twice in a row to avoid misreads
        if v == last {
            last = ""
            handle(v)
        } else {
            last = v
        }
    }

    private func handle(_ raw: String) {
        guard let c = classifyCode(raw) else {
            model.dialogs.toast(model.t("scan.invalid"))
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        phase = "busy"
        code = c.code
        let items = model.store.items
        let key = model.settings.googleBooksKey
        Task { @MainActor in
            let d0 = items.first { $0.isbn == c.code }
            var list: [Candidate] = []
            if c.type == "isbn" {
                if let one = await Lookup.shared.lookupIsbn(c.code, googleKey: key) { list = [one] }
            } else {
                list = await Lookup.shared.lookupEan(c.code)
            }
            dup = d0 ?? list.first.flatMap { findDuplicate(items, title: $0.title, creators: $0.creators) }
            found = list
            phase = list.isEmpty ? "none" : "found"
        }
    }

    private func add(_ c: Candidate) {
        let r = room ?? model.settings.lastRoom
        var draft = c.data
        draft["owned"] = mode != "wish"
        draft["room"] = mode == "wish" || r.isEmpty ? NSNull() : r
        draft["source"] = "isbn"
        if let item = model.store.addItems([draft]).first { added.insert(item, at: 0) }
        model.updateSettings { $0.lastRoom = r }
        phase = "scan"
    }

    private func edit(_ data: JSONObject) {
        let r = room ?? model.settings.lastRoom
        var draft = data
        draft["owned"] = mode != "wish"
        draft["room"] = r.isEmpty ? NSNull() : r
        draft["source"] = "isbn"
        router.openForm(draft: draft)
        phase = "scan"
    }
}
