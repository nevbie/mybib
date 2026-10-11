import SwiftUI
import MybibCore

private struct Way: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let text: String
    let action: () -> Void
}

struct AddView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var searching = false
    @State private var picked: Candidate?

    private var ways: [Way] {
        let hasKey = !model.settings.claudeKey.isEmpty
        return [
            Way(id: 0, icon: "barcode.viewfinder", title: model.t("add.scan"), text: model.t("add.scanText")) { router.push(.scan) },
            Way(id: 1, icon: "camera.viewfinder", title: model.t("add.shelf"), text: hasKey ? model.t("add.shelfText") : model.t("add.shelfTextNoKey")) {
                router.push(.photo("shelf"))
            },
            Way(id: 2, icon: "photo", title: model.t("add.cover"), text: model.t("add.coverText")) { router.push(.photo("cover")) },
            Way(id: 3, icon: "magnifyingglass", title: model.t("add.search"), text: model.t("add.searchText")) { searching = true },
            Way(id: 4, icon: "square.and.pencil", title: model.t("add.manual"), text: model.t("add.manualText")) { router.openForm() },
            Way(id: 5, icon: "sparkles", title: model.t("bulk.title"), text: model.t("bulk.short")) { router.push(.bulk) },
            Way(id: 6, icon: "square.and.arrow.down", title: model.t("add.import"), text: model.t("add.importText")) { model.importing = true },
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(ways) { w in
                    Button(action: w.action) {
                        HStack(spacing: 14) {
                            Image(systemName: w.icon).font(.title2).foregroundStyle(brandColor).frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.title).fontWeight(.semibold).foregroundStyle(Color.primary)
                                Text(w.text).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text(model.t("add.tip"))
            }
        }
        .navigationTitle(model.t("nav.add"))
        .sheet(isPresented: $searching, onDismiss: {
            // open the form once the search sheet is gone
            if let c = picked {
                picked = nil
                router.openForm(draft: c.draft())
            }
        }) {
            SearchSheet(kind: "book", title: "", creator: "") { picked = $0 }
                .environment(model)
        }
    }
}
