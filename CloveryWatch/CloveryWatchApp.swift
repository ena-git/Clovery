import SwiftUI

@main
struct CloveryWatchApp: App {
    @StateObject private var store = WatchSessionStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
