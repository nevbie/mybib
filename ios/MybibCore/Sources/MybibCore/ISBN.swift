import Foundation

private let notCodeChar = Rx("[^0-9X]")
private let innerX = Rx("X(?=.)")
private let isbn10Shape = Rx("^[0-9]{9}[0-9X]$")
private let ean13Shape = Rx("^[0-9]{13}$")
private let digitsOnly = Rx("^[0-9]+$")

private func digits(_ s: String) -> [Int] { s.map { $0 == "X" ? 10 : Int(String($0)) ?? 0 } }

/// Strip everything but digits (and a trailing X of an ISBN-10).
public func cleanCode(_ raw: String) -> String {
    innerX.replace(notCodeChar.replace(raw.uppercased(), ""), "")
}

public func isValidIsbn10(_ s: String) -> Bool {
    guard isbn10Shape.test(s) else { return false }
    let d = digits(s)
    let sum = (0..<10).reduce(0) { $0 + d[$1] * (10 - $1) }
    return sum % 11 == 0
}

/// EAN-13 checksum – ISBN-13 is an EAN-13 starting with 978/979.
public func isValidEan13(_ s: String) -> Bool {
    guard ean13Shape.test(s) else { return false }
    let d = digits(s)
    let sum = (0..<12).reduce(0) { $0 + d[$1] * ($1 % 2 == 1 ? 3 : 1) }
    return (10 - sum % 10) % 10 == d[12]
}

public func isIsbn13(_ s: String) -> Bool {
    isValidEan13(s) && (s.hasPrefix("978") || s.hasPrefix("979"))
}

public func isbn10to13(_ s: String) -> String {
    let core: String = "978" + String(s.prefix(9))
    let d = digits(core)
    let sum = (0..<12).reduce(0) { $0 + d[$1] * ($1 % 2 == 1 ? 3 : 1) }
    return core + String((10 - sum % 10) % 10)
}

public struct ScannedCode: Equatable, Sendable {
    /// "isbn" (normalised to 13 digits) or "ean"
    public let type: String
    public let code: String
    public init(type: String, code: String) {
        self.type = type
        self.code = code
    }
}

/// Classify a scanned or typed code; nil when invalid.
public func classifyCode(_ raw: String) -> ScannedCode? {
    let s = cleanCode(raw)
    if s.count == 10, isValidIsbn10(s) { return ScannedCode(type: "isbn", code: isbn10to13(s)) }
    if s.count == 13, isIsbn13(s) { return ScannedCode(type: "isbn", code: s) }
    if s.count == 13, isValidEan13(s) { return ScannedCode(type: "ean", code: s) }
    // UPC-A (12 digits) – common on US CDs / DVDs
    if s.count == 12, isValidEan13("0" + s) { return ScannedCode(type: "ean", code: s) }
    if s.count == 8, digitsOnly.test(s) { return ScannedCode(type: "ean", code: s) }
    return nil
}
