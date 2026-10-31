import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
            WantlistView()
                .tabItem { Label("Wantlist", systemImage: "heart") }
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.stack") }
            DigLogView()
                .tabItem { Label("Dig Log", systemImage: "book.closed") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .badge(model.pending.isEmpty ? 0 : model.pending.count)
        }
    }
}
