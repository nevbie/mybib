import SwiftUI
import UniformTypeIdentifiers
import MybibCore

@main
struct MybibApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(brandColor)
        }
    }
}

let brandColor = Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255)

/// Four tabs like the Android NavigationBar, each with its own navigation stack.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if model.store.ready {
                tabs
            } else {
                Text(model.t("app.loading"))
            }
        }
        .modifier(DialogHost(center: model.dialogs, ok: model.t("ok"), cancel: model.cancelText))
        .fileImporter(isPresented: Binding(get: { model.importing }, set: { model.importing = $0 }), allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await model.importFile(url) }
            }
        }
        .onChange(of: phase) { _, p in
            // don't lose a debounced write when the app goes to the background
            if p != .active { model.store.save() }
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
            TabRoot(router: model.routers[0]) { LibraryView() }
                .tabItem { Label(model.t("nav.library"), systemImage: "books.vertical") }
                .badge(model.store.items.filter(\.needsCheck).count)
                .tag(0)
            TabRoot(router: model.routers[1]) { AddView() }
                .tabItem { Label(model.t("nav.add"), systemImage: "plus.circle") }
                .tag(1)
            TabRoot(router: model.routers[2]) { PlacesView() }
                .tabItem { Label(model.t("nav.places"), systemImage: "house") }
                .tag(2)
            TabRoot(router: model.routers[3]) { SettingsView() }
                .tabItem { Label(model.t("nav.settingsShort"), systemImage: "gearshape") }
                .tag(3)
        }
    }
}
