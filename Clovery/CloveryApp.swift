import SwiftUI
import UIKit

@main
struct CloveryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
#if targetEnvironment(macCatalyst)
                .onAppear { MacWindowConfigurator.apply() }
#endif
        }
    }
}

// Registers for silent remote push so CloudKit can notify this device the
// moment another device writes a new diary entry, instead of only catching
// up on next launch.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return true
        }
        WatchBridge.shared.activate()
        return true
    }

}

#if targetEnvironment(macCatalyst)
// The scene only exists once the first window appears, so size limits are applied here
// rather than at launch. Keeping the window portrait-ish lets the page scale proportionally.
enum MacWindowConfigurator {
    private static var didSetInitialSize = false

    static func apply() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            if let titlebar = scene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
            }
            scene.sizeRestrictions?.minimumSize = CGSize(width: 500, height: 720)
            scene.sizeRestrictions?.maximumSize = CGSize(width: 800, height: 2000)
            guard !didSetInitialSize else { return }
            didSetInitialSize = true
            if #available(macCatalyst 16.0, *) {
                var frame = scene.effectiveGeometry.systemFrame
                frame.size = CGSize(width: 560, height: 860)
                scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { _ in }
            }
        }
    }
}
#endif
