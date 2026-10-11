import SwiftUI
import Observation
import MybibCore

/// A new entry (optionally prefilled from `draft`) or an existing one (`id`) to edit.
final class FormRequest: Hashable {
    let id: String?
    let draft: JSONObject?

    init(id: String? = nil, draft: JSONObject? = nil) {
        self.id = id
        self.draft = draft
    }

    static func == (a: FormRequest, b: FormRequest) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

enum Route: Hashable {
    case item(String)
    case form(FormRequest)
    case scan
    /// "shelf" or "cover"
    case photo(String)
    case bulk
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ r: Route) { path.append(r) }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func openForm(id: String? = nil, draft: JSONObject? = nil) { push(.form(FormRequest(id: id, draft: draft))) }
}

struct TabRoot<Content: View>: View {
    @Bindable var router: Router
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $router.path) {
            content()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .environment(router)
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .item(let id): ItemDetailView(id: id)
        case .form(let request): ItemFormView(request: request)
        case .scan: ScanView()
        case .photo(let mode): PhotoView(mode: mode)
        case .bulk: BulkView()
        }
    }
}
