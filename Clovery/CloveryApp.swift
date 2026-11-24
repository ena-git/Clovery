import CloudKit
import SwiftUI
import UIKit

@main
struct CloveryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .onOpenURL { url in
                    WebViewCoordinatorBridge.shared.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                WebViewCoordinatorBridge.shared.refreshBoardEntitlement()
                WebViewCoordinatorBridge.shared.refreshICloudSync()
                WebViewCoordinatorBridge.shared.flushPendingWatchEntries()
            }
        }
    }
}

// Registers for silent remote push so CloudKit can notify this device the
// moment another device writes a new diary entry, instead of only catching
// up on next launch.
class AppDelegate: NSObject, UIApplicationDelegate {
    private var accountObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return true
        }
        WatchSessionManager.shared.onPendingEntriesAvailable = { entries in
            Task { @MainActor in
                WebViewCoordinatorBridge.shared.deliverWatchEntries(entries)
            }
        }
        WatchSessionManager.shared.activate()
        application.registerForRemoteNotifications()
        CloudKitSync.shared.setupSubscriptionIfNeeded()
        accountObserver = NotificationCenter.default.addObserver(
            forName: CloudKitSync.accountDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WebViewCoordinatorBridge.shared.refreshICloudSync()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Clovery CloudKit] remote notification registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        WebViewCoordinatorBridge.shared.handleRemoteCloudKitNotification {
            completionHandler(.newData)
        }
    }
}
