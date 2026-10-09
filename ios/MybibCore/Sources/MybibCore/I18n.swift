import Foundation

/// The texts from shared/strings.json: `{"de": {key: text}, "en": {…}}` with `{placeholder}`s.
/// The app loads it from its bundle, the tests straight from the repository.
public struct Strings: Sendable {
    public let table: [String: [String: String]]

    public init(table: [String: [String: String]]) {
        self.table = table
    }

    public init(contentsOf url: URL) throws {
        table = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    /// Texts from `url`; empty (keys are shown as they are) when missing or unreadable.
    public static func load(_ url: URL?) -> Strings {
        guard let url, let s = try? Strings(contentsOf: url) else { return Strings(table: [:]) }
        return s
    }

    /// Translate a key, filling `{name}` placeholders. Falls back to English, then to the key itself.
    public func t(_ lang: String, _ key: String, _ vars: [String: Any] = [:]) -> String {
        var s = table[lang]?[key] ?? table["en"]?[key] ?? key
        for (k, v) in vars {
            s = s.replacingOccurrences(of: "{\(k)}", with: "\(v)")
        }
        return s
    }
}
