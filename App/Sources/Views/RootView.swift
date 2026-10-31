import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case scan, wantlist, collection, digLog, settings

        init(_ screen: StartScreen?) {
            switch screen {
            case .wantlist: self = .wantlist
            case .collection: self = .collection
            case .diglog: self = .digLog
            case .settings: self = .settings
            case .scan, .manual, .result, .pressings, nil: self = .scan
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab

    init(startScreen: StartScreen? = nil) {
        _tab = State(initialValue: Tab(startScreen))
    }

    var body: some View {
        TabView(selection: $tab) {
            ScanView()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                .tag(Tab.scan)
            WantlistView()
                .tabItem { Label("Wantlist", systemImage: "heart") }
                .tag(Tab.wantlist)
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.stack") }
                .tag(Tab.collection)
            DigLogView()
                .tabItem { Label("Dig Log", systemImage: "book.closed") }
                .tag(Tab.digLog)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .badge(model.pending.isEmpty ? 0 : model.pending.count)
                .tag(Tab.settings)
        }
    }
}
