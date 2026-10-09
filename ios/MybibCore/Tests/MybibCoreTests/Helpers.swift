import Foundation
import XCTest
@testable import MybibCore

func item(_ p: JSONObject) -> Item {
    var d: JSONObject = ["title": "x"]
    d.merge(p) { _, new in new }
    return normalizeItem(d, now: "2026-01-01T00:00:00.000Z")
}

func ids(_ l: [Item]) -> [String] { l.map(\.id) }

/// The repository root, found from this file's path (ios/MybibCore/Tests/MybibCoreTests/Helpers.swift).
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // MybibCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // MybibCore
    .deletingLastPathComponent() // ios
    .deletingLastPathComponent()

func assertJSON(_ a: Any?, _ b: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(jsonEqual(a, b), "\(String(describing: a)) != \(String(describing: b))", file: file, line: line)
}

/// Canned HTTP answers; HEAD requests (cover probes) always find an image.
final class MockHTTP: HTTPClient, @unchecked Sendable {
    let handler: (URLRequest) -> (Int, Any)
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ handler: @escaping (URLRequest) -> (Int, Any)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        lock.unlock()
        let url = request.url ?? URL(fileURLWithPath: "/")
        if request.httpMethod == "HEAD" {
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg", "Content-Length": "5000"])!)
        }
        let (status, body) = handler(request)
        let data = (try? encodeJSON(body)) ?? Data()
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
