import SwiftUI
import UniformTypeIdentifiers
import MybibCore

private let models: [Choice<String>] = [Choice("claude-opus-5-5", "Claude Opus 5.5"), Choice("claude-sonnet-5-5", "Claude Sonnet 5.5")]

/// Plain text file for the export dialog.
struct TextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText, .plainText]
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var claudeKey = ""
    @State private var googleKey = ""
    @State private var showKey = false
    @State private var loaded = false
    @State private var exporting = false
    @State private var exportDoc: TextFile?
    @State private var exportType: UTType = .json
    @State private var exportName = ""
    @State private var shareFile: ShareFile?

    private var stamp: String { today() }
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty || v.hasSuffix(".\(b)") ? v : "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section(model.t("settings.lang")) {
                Picker(model.t("settings.lang"), selection: Binding(get: { model.lang }, set: { l in model.updateSettings { $0.lang = l } })) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }
            aiSection
            lookupSection
            CategoriesSection()
            dataSection
            Section {
                Text("mybib · \(model.t("settings.about")) · \(model.t("settings.version", ["v": version]))")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(model.t("nav.settings"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            claudeKey = model.settings.claudeKey
            googleKey = model.settings.googleBooksKey
        }
        .onChange(of: claudeKey) { _, v in
            let k = v.trimmed
            if k != model.settings.claudeKey { model.updateSettings { $0.claudeKey = k } }
        }
        .onChange(of: googleKey) { _, v in
            let k = v.trimmed
            if k != model.settings.googleBooksKey { model.updateSettings { $0.googleBooksKey = k } }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: exportType, defaultFilename: exportName) { result in
            if case .success = result { model.dialogs.toast(model.t("data.saved")) }
        }
        .sheet(item: $shareFile) { f in
            ActivityView(items: [f.url]).presentationDetents([.medium, .large])
        }
    }

    private var aiSection: some View {
        Section {
            Text(model.t("settings.aiText")).font(.caption).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("settings.claudeKey")).font(.caption).foregroundStyle(.secondary)
                    if showKey {
                        TextField("sk-ant-…", text: $claudeKey)
                    } else {
                        SecureField("sk-ant-…", text: $claudeKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }
            let current = models.contains(where: { $0.value == model.settings.claudeModel }) ? model.settings.claudeModel : models[0].value
            OptionPicker(label: model.t("settings.model"), value: current,
                         options: models.map { Choice($0.value, "\($0.label) – \(model.t("settings.model.\($0.value)"))") }) { v in
                model.updateSettings { $0.claudeModel = v }
            }
            Text(model.t("settings.aiPrivacy")).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(model.t("settings.ai"))
        }
    }

    private var lookupSection: some View {
        Section {
            Text(model.t("settings.lookupText")).font(.caption).foregroundStyle(.secondary)
            LabeledField(label: model.t("settings.googleKey"), text: $googleKey, hint: model.t("optional"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            DisclosureGroup(model.t("settings.googleHow")) {
                ForEach(1...4, id: \.self) { n in
                    HStack(alignment: .top) {
                        Text("\(n).")
                        Text(model.t("settings.googleHow\(n)"))
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text(model.t("settings.lookup"))
        }
    }

    private var dataSection: some View {
        Section {
            Text(model.t("settings.dataText", ["n": model.store.items.count])).font(.caption).foregroundStyle(.secondary)
            Button {
                export(exportJSON(), type: .json, name: "mybib-\(stamp)")
            } label: {
                Label(model.t("data.exportJson"), systemImage: "square.and.arrow.down")
            }
            Button {
                share(exportJSON(), name: "mybib-\(stamp).json")
            } label: {
                Label(model.t("data.exportJsonShare"), systemImage: "square.and.arrow.up")
            }
            Button {
                export(toCSV(model.store.items), type: .commaSeparatedText, name: "mybib-\(stamp)")
            } label: {
                Label(model.t("data.exportCsv"), systemImage: "tablecells")
            }
            Button {
                share(toCSV(model.store.items), name: "mybib-\(stamp).csv")
            } label: {
                Label(model.t("data.exportCsvShare"), systemImage: "square.and.arrow.up.on.square")
            }
            Button {
                model.importing = true
            } label: {
                Label(model.t("data.import"), systemImage: "square.and.arrow.down.on.square")
            }
            Button(role: .destructive) {
                Task { await wipe() }
            } label: {
                Label(model.t("data.wipe"), systemImage: "trash")
            }
            .disabled(model.store.items.isEmpty)
        } header: {
            Text(model.t("settings.data"))
        }
    }

    private func exportJSON() -> String {
        guard let data = try? encodeJSON(toExport(model.store.items)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func export(_ text: String, type: UTType, name: String) {
        exportDoc = TextFile(text: text)
        exportType = type
        exportName = name
        exporting = true
    }

    private func share(_ text: String, name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            shareFile = ShareFile(url: url)
        } catch {
            model.dialogs.toast(error.localizedDescription)
        }
    }

    private func wipe() async {
        guard await model.dialogs.confirm(model.t("data.wipeConfirm", ["n": model.store.items.count])) else { return }
        let typed = await model.dialogs.prompt(model.t("data.wipeType"))
        if typed?.trimmed == "OK" { model.store.replaceAll([]) }
    }
}

private struct CategoriesSection: View {
    @Environment(AppModel.self) private var model

    private var cats: [String] { model.store.categories() }

    private var catCount: [String: Int] {
        var m: [String: Int] = [:]
        for i in model.store.items {
            if let c = i.category { m[c, default: 0] += 1 }
        }
        return m
    }

    private func saveCats(_ list: [String]) {
        var seen = Set<String>()
        let clean = list.filter { !$0.isEmpty && seen.insert($0).inserted }
        model.updateSettings { $0.categories = clean }
    }

    var body: some View {
        let counts = catCount
        Section {
            Text(model.t("settings.categoriesText")).font(.caption).foregroundStyle(.secondary)
            ForEach(cats, id: \.self) { c in
                HStack {
                    Text("\(model.catLabel(c))  (\(counts[c] ?? 0))")
                    Spacer()
                    Button {
                        Task { await rename(c) }
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(model.t("places.rename"))
                    Button {
                        Task { await remove(c, count: counts[c] ?? 0) }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(model.t("places.remove"))
                }
                .buttonStyle(.borderless)
            }
            Button {
                Task { await add() }
            } label: {
                Label(model.t("cat.add"), systemImage: "plus")
            }
            if !model.settings.categories.isEmpty {
                Button(model.t("cat.reset")) {
                    Task {
                        if await model.dialogs.confirm(model.t("cat.resetConfirm")) {
                            model.updateSettings { $0.categories = [] }
                        }
                    }
                }
            }
        } header: {
            Text(model.t("settings.categories"))
        }
    }

    private func add() async {
        guard let name = await model.dialogs.prompt(model.t("cat.new"))?.trimmed, let c = toCategory(name) else { return }
        saveCats(cats + [c])
    }

    private func rename(_ c: String) async {
        let label = model.catLabel(c)
        guard let name = await model.dialogs.prompt(model.t("cat.rename", ["name": label]), initial: label)?.trimmed,
              !name.isEmpty, name != label, let to = toCategory(name) else { return }
        let list = cats
        if list.contains(to) {
            let ok = await model.dialogs.confirm(model.t("cat.mergeConfirm", ["from": label, "to": model.catLabel(to)]))
            if !ok { return }
        }
        model.store.moveCategory(c, to)
        saveCats(list.map { $0 == c ? to : $0 })
    }

    private func remove(_ c: String, count n: Int) async {
        let list = cats
        guard await model.dialogs.confirm(model.t("cat.removeConfirm", ["name": model.catLabel(c), "n": n])) else { return }
        model.store.moveCategory(c, "")
        saveCats(list.filter { $0 != c })
    }
}
