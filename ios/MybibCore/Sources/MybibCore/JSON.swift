import Foundation

/// Loosely typed JSON object, like Dart's `Map<String, dynamic>`.
/// A missing key, `NSNull()` or a boxed nil all mean null. Patches use `NSNull()` to clear a value.
public typealias JSONObject = [String: Any]

private protocol AnyOptional {
    var flatValue: Any? { get }
}

extension Optional: AnyOptional {
    fileprivate var flatValue: Any? {
        switch self {
        case .none: return nil
        case .some(let w): return flat(w)
        }
    }
}

/// Plain value or nil: unwraps NSNull and Optionals boxed in `Any`.
public func flat(_ v: Any?) -> Any? {
    guard let v else { return nil }
    if v is NSNull { return nil }
    if let o = v as? AnyOptional { return o.flatValue }
    return v
}

private func isBoolNumber(_ n: NSNumber) -> Bool {
    CFGetTypeID(n) == CFBooleanGetTypeID()
}

/// Only real booleans (JSON true/false or a Swift Bool) – never 0 / 1.
public func jBool(_ v: Any?) -> Bool? {
    guard let v = flat(v), let n = v as? NSNumber, isBoolNumber(n) else { return nil }
    return n.boolValue
}

/// Number for JSON number or numeric string; booleans and fractions of strings don't count.
public func jInt(_ v: Any?) -> Int? {
    guard let v = flat(v) else { return nil }
    if let s = v as? String { return Int(s.trimmed) }
    if let n = v as? NSNumber, !isBoolNumber(n) {
        let d = n.doubleValue
        guard d.isFinite, abs(d) < 9e15 else { return nil }
        return Int(d.rounded())
    }
    return nil
}

/// Trimmed non-empty string; numbers become their text.
public func jStr(_ v: Any?) -> String? {
    guard let v = flat(v) else { return nil }
    if let s = v as? String {
        let t = s.trimmed
        return t.isEmpty ? nil : t
    }
    if let n = v as? NSNumber, !isBoolNumber(n) {
        let d = n.doubleValue
        if d.isFinite, d == d.rounded(), abs(d) < 9e15 { return String(Int(d)) }
        return n.stringValue
    }
    return nil
}

/// A list of strings, or one string like "Mary Auld / Elisa Paganelli" split into names.
public func jStrList(_ v: Any?) -> [String] {
    let v = flat(v)
    if let a = v as? [Any] { return a.compactMap { jStr($0) } }
    if let s = v as? String, !s.trimmed.isEmpty {
        return Rx.listSplit.split(s).map { $0.trimmed }.filter { !$0.isEmpty }
    }
    return []
}

/// Null, empty string or empty list.
public func isEmptyValue(_ v: Any?) -> Bool {
    guard let v = flat(v) else { return true }
    if let s = v as? String { return s.isEmpty }
    if let a = v as? [Any] { return a.isEmpty }
    return false
}

/// Dictionary without its null values (like Dart's `..removeWhere((k, v) => v == null)`).
public func compact(_ d: [String: Any?]) -> JSONObject {
    var out = JSONObject()
    for (k, v) in d {
        if let v = flat(v) { out[k] = v }
    }
    return out
}

/// Deep equality of JSON-like values (dictionaries, arrays, numbers, strings).
public func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (flat(a), flat(b)) {
    case (nil, nil): return true
    case let (x?, y?):
        if let x = x as? JSONObject, let y = y as? JSONObject { return NSDictionary(dictionary: x).isEqual(to: y) }
        if let x = x as? [Any], let y = y as? [Any] { return NSArray(array: x).isEqual(to: y) }
        if let x = x as? NSObject, let y = y as? NSObject { return x.isEqual(y) }
        return false
    default: return false
    }
}

public func decodeJSON(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

public func encodeJSON(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
}

public extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// nil for an empty string (Dart's `ifEmpty`).
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Small wrapper around NSRegularExpression with Dart-like helpers. Patterns are constants covered by the tests.
public final class Rx: @unchecked Sendable {
    let re: NSRegularExpression

    public init(_ pattern: String, caseInsensitive: Bool = false) {
        re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private func whole(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }

    public func test(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: whole(s)) != nil
    }

    public func replace(_ s: String, _ with: String) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: whole(s), withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }

    public func first(_ s: String) -> String? {
        guard let m = re.firstMatch(in: s, options: [], range: whole(s)), let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    /// Pieces between the matches, like Dart's `String.split(RegExp)`.
    public func split(_ s: String) -> [String] {
        var out: [String] = []
        var start = s.startIndex
        for m in re.matches(in: s, options: [], range: whole(s)) {
            guard let r = Range(m.range, in: s), !r.isEmpty, r.lowerBound >= start else { continue }
            out.append(String(s[start..<r.lowerBound]))
            start = r.upperBound
        }
        out.append(String(s[start...]))
        return out
    }

    static let listSplit = Rx(#"\s*[;/]\s*|\s+&\s+"#)
    static let nonWord = Rx(#"[^\p{L}\p{N}]+"#)
    static let spaces = Rx(#"\s+"#)
    static let parens = Rx(#"\([^)]*\)"#)
    static let articles = Rx(#"^(der|die|das|ein|eine|the|a|an|le|la|les|el|los|las)\s+"#, caseInsensitive: true)
    static let notIsbnChar = Rx("[^0-9Xx]")
    static let csvSpecial = Rx("[\";\n]")
    static let year = Rx("[0-9]{4}")
}
