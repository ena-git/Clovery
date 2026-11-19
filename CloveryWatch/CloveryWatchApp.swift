import SwiftUI

@main
struct CloveryWatchApp: App {
    @StateObject private var store: WatchStore

    init() {
        WFont.registerBundledFonts()
        _store = StateObject(wrappedValue: WatchStore())
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
    }
}
