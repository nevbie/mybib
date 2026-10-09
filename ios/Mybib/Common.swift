import SwiftUI
import UIKit
import MybibCore

let kindIcon: [String: String] = ["book": "📖", "game": "🎲", "dvd": "📀", "cd": "💿"]

let amber = Color(red: 1.0, green: 0.70, blue: 0.0)
let warnBackground = Color.yellow.opacity(0.25)

/// Value + label for pickers and menus.
struct Choice<V: Hashable>: Identifiable {
    let value: V
    let label: String
    var id: V { value }

    init(_ value: V, _ label: String) {
        self.value = value
        self.label = label
    }
}

extension Choice: Sendable where V: Sendable {}

// MARK: - covers

/// Decoded own photos and downloaded covers, kept in memory so lists scroll smoothly.
final class CoverCache: @unchecked Sendable {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, UIImage>()

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func image(dataURL: String, key: String) -> UIImage? {
        if let i = cached(key) { return i }
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]), options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    func image(url: String) async -> UIImage? {
        if let i = cached(url) { return i }
        guard let u = URL(string: url), let reply = try? await URLSession.shared.data(from: u), let img = UIImage(data: reply.0) else { return nil }
        cache.setObject(img, forKey: url as NSString)
        return img
    }
}

/// Cover image with a coloured placeholder showing the kind (and title when large).
struct CoverImage: View {
    let title: String
    let kind: String
    var coverUrl: String?
    var coverData: String?
    var large = false
    @State private var loaded: UIImage?

    init(title: String, kind: String, coverUrl: String? = nil, coverData: String? = nil, large: Bool = false) {
        self.title = title
        self.kind = kind
        self.coverUrl = coverUrl
        self.coverData = coverData
        self.large = large
    }

    init(item: Item, large: Bool = false) {
        self.init(title: item.title, kind: item.kind, coverUrl: item.coverUrl, coverData: item.coverData, large: large)
    }

    private var key: String {
        if let d = coverData { return "data:\(d.count):\(d.hashValue)" }
        return coverUrl ?? ""
    }

    private var hue: Double {
        var h = 0
        for c in title.utf16 { h = (h * 31 + Int(c)) % 360 }
        return Double(h) / 360
    }

    var body: some View {
        ZStack {
            if let img = loaded ?? CoverCache.shared.cached(key) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: large ? 110 : 44, height: large ? 160 : 64)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: key) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            // HSL(hue, 45 %, 55 %) like the other apps
            Color(hue: hue, saturation: 0.538, brightness: 0.7525)
            VStack(spacing: 6) {
                Text(kindIcon[kind] ?? "📖").font(.system(size: large ? 20 : 16))
                if large {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                }
            }
            .padding(6)
        }
    }

    private func load() async {
        loaded = nil
        if let d = coverData {
            loaded = CoverCache.shared.image(dataURL: d, key: key)
        } else if let u = coverUrl {
            loaded = await CoverCache.shared.image(url: u)
        }
    }
}

// MARK: - small pieces

struct Stars: View {
    @Environment(AppModel.self) private var model
    let value: Int
    var small = false
    var onChange: ((Int) -> Void)?

    var body: some View {
        if let onChange {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        onChange(value == n ? 0 : n)
                    } label: {
                        Text("★").font(.system(size: 30)).foregroundStyle(n <= value ? amber : Color.secondary.opacity(0.3))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.t("rating.n", ["n": n]))
                }
            }
        } else if value > 0 {
            HStack(spacing: 0) {
                Text(String(repeating: "★", count: value)).foregroundStyle(amber)
                Text(String(repeating: "★", count: 5 - value)).foregroundStyle(Color.secondary.opacity(0.3))
            }
            .font(.system(size: small ? 12 : 16))
        }
    }
}

/// Small rounded label (status, format, wishlist …).
struct Pill: View {
    let text: String
    var color: Color = Color.secondary.opacity(0.15)
    var outlined = false

    init(_ text: String, color: Color = Color.secondary.opacity(0.15), outlined: Bool = false) {
        self.text = text
        self.color = color
        self.outlined = outlined
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(outlined ? Color.secondary : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background {
                if outlined {
                    Capsule().stroke(Color.secondary.opacity(0.4))
                } else {
                    Capsule().fill(color)
                }
            }
    }
}

/// Lays its children out left to right and wraps into new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + s.width > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            width = max(width, x + s.width)
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: width, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

/// Filter chip.
struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(on ? brandColor.opacity(0.2) : Color.clear))
                .overlay(Capsule().stroke(on ? brandColor : Color.secondary.opacity(0.4)))
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Text field with a small label above it (like a Material text field).
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var hint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: $text)
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard != .default)
        }
    }
}

/// Text field with suggestions (rooms, people).
struct SuggestField: View {
    let label: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        HStack {
            LabeledField(label: label, text: $text)
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { o in
                        Button(o) { text = o }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle").imageScale(.large)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Menu picker with a label, for value lists.
struct OptionPicker<V: Hashable>: View {
    let label: String
    let value: V
    let options: [Choice<V>]
    let onChange: (V) -> Void

    var body: some View {
        Picker(label, selection: Binding(get: { value }, set: { onChange($0) })) {
            ForEach(options) { o in
                Text(o.label).tag(o.value)
            }
        }
        .pickerStyle(.menu)
    }
}

/// Category picker grouped like the default list; own categories come last.
/// `extra` adds entries before the list (e.g. "unchanged" / "all").
struct CategoryMenu: View {
    @Environment(AppModel.self) private var model
    let value: String
    var extra: [Choice<String>] = []
    var noneValue = ""
    var label: String?
    let onChange: (String) -> Void

    private var current: String {
        if let e = extra.first(where: { $0.value == value }) { return e.label }
        if value != noneValue, model.store.categories().contains(value) { return model.catLabel(value) }
        return model.t("cat.none")
    }

    var body: some View {
        let cats = model.store.categories()
        let grouped = Set(defaultCategoryIds)
        LabeledContent(label ?? model.t("field.category")) {
            Menu {
                ForEach(extra) { e in
                    Button(e.label) { onChange(e.value) }
                }
                Button(model.t("cat.none")) { onChange(noneValue) }
                ForEach(defaultCategoryGroups.indices, id: \.self) { gi in
                    let g = defaultCategoryGroups[gi]
                    let ids = g.items.map(\.id).filter { cats.contains($0) }
                    if !ids.isEmpty {
                        Section(model.lang == "de" ? g.de : g.en) {
                            ForEach(ids, id: \.self) { id in
                                Button(model.catLabel(id)) { onChange(id) }
                            }
                        }
                    }
                }
                let own = cats.filter { !grouped.contains($0) }
                if !own.isEmpty {
                    Section(model.t("cat.own")) {
                        ForEach(own, id: \.self) { c in
                            Button(c) { onChange(c) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

/// One row in the library list.
struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: Item
    /// non-nil in selection mode
    var selected: Bool?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let selected {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(brandColor)
                    .padding(.top, 20)
            }
            CoverImage(item: item)
            VStack(alignment: .leading, spacing: 3) {
                titleText
                if !item.creators.isEmpty {
                    Text(item.creators.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                }
                badges
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var titleText: Text {
        let t = Text(item.title).fontWeight(.semibold)
        guard let v = item.volume else { return t }
        return t + Text(" · \(v)").foregroundColor(.secondary)
    }

    private var badges: some View {
        FlowLayout(spacing: 6, lineSpacing: 3) {
            if item.rating > 0 { Stars(value: item.rating, small: true) }
            if item.status != "none" {
                Pill(model.t("status.\(item.kind).\(item.status)"), color: item.status == "done" ? brandColor.opacity(0.18) : Color.blue.opacity(0.15))
            }
            if item.format != "physical" { Pill(model.t("format.\(item.format)")) }
            if !item.owned { Pill(model.t("scope.wish"), color: Color.pink.opacity(0.2)) }
            if let c = item.category { Pill(model.catLabel(c), outlined: true) }
            if item.recommend { Text("👍").font(.system(size: 12)) }
            if let loan = item.openLoan { Pill("↗ \(loan.to)", color: Color.purple.opacity(0.18)) }
            if item.needsCheck { Pill("?", color: amber.opacity(0.4)) }
            if let r = item.room { Text(r).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

/// Small coloured note box.
struct NoteBox<Content: View>: View {
    var color: Color = warnBackground
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(color))
    }
}

/// UIActivityViewController for sharing files.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
