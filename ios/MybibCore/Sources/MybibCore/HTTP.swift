import Foundation

/// The little HTTP the app needs; swappable for tests.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTP: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Percent-encode a query value (everything but letters, digits and -._~).
public func encodeQuery(_ s: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
}

/// Run `f` on all elements concurrently, results in the original order.
func concurrentMap<T: Sendable, R: Sendable>(_ list: [T], _ f: @escaping @Sendable (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self, returning: [R].self) { group in
        for (i, x) in list.enumerated() {
            group.addTask { (i, await f(x)) }
        }
        var out: [(Int, R)] = []
        for await r in group { out.append(r) }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
