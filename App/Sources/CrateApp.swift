import SwiftUI

@main
struct CrateApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(startScreen: model.initialStartScreen)
                .environment(model)
                .task { await model.start() }
        }
    }
}
