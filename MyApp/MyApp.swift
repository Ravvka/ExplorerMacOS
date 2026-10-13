import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ExplorerView()
        }
        .defaultSize(width: 1000, height: 650)
        .windowStyle(.hiddenTitleBar)
    }
}
