import SwiftUI
import WebKit
import UIKit
import Combine
import UserNotifications
import StoreKit
import WidgetKit
import OSLog

struct WebView: UIViewRepresentable {

    // MARK: – Message handler (haptic + notifications + iCloud)
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UNUserNotificationCenterDelegate {

        // Weak ref so we can push iCloud data into the running WebView
        weak var webView: WKWebView?
        private(set) var didFinishInitialLoad = false
        private var boardEntitlementCancellable: AnyCancellable?
        private var isCloudKitPulling = false
        private lazy var boardEntitlementReporter = BoardEntitlementReporter(
            currentEntitlement: { BoardStore.shared.isUnlocked },
            reportUnlock: { [weak self] unlocked in
                self?.webView?.evaluateJavaScript(
                    BridgeJavaScript.boardUnlockStatus(unlocked),
                    completionHandler: nil
                )
            }
        )
        private let photoLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.clovery.app",
            category: "Photos"
        )
        private let photoStore: PhotoStoring
        private let imageExporter: ImageExporting
        private let trialStore: KeychainTrialStore

        init(
            photoStore: PhotoStoring = PhotoStore(),
            imageExporter: ImageExporting = ImageExportService(),
            trialStore: KeychainTrialStore = .shared
        ) {
            self.photoStore = photoStore
            self.imageExporter = imageExporter
            self.trialStore = trialStore
            super.init()
        }

        // MARK: Screenshot protection (UITextField isSecureTextEntry trick)
        private var screenshotProtectionField: UITextField?

        @MainActor
        private func applyBoardProtection() {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                return
            }
            guard let wv = webView,
                  let parent = wv.superview,
                  screenshotProtectionField == nil else { return }
            let tf = UITextField()
            tf.isSecureTextEntry = true
            tf.backgroundColor = .clear
            tf.frame = wv.frame
            tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            if let idx = parent.subviews.firstIndex(of: wv) {
                parent.insertSubview(tf, at: idx)
            } else {
                parent.addSubview(tf)
            }
            tf.addSubview(wv)
            wv.frame = tf.bounds
            wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            screenshotProtectionField = tf
        }

        @MainActor
        private func removeBoardProtection() {
            guard let tf = screenshotProtectionField,
                  let wv = webView,
                  let parent = tf.superview else { return }
            if let idx = parent.subviews.firstIndex(of: tf) {
                parent.insertSubview(wv, at: idx)
            } else {
                parent.addSubview(wv)
            }
            wv.frame = tf.frame
            wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tf.removeFromSuperview()
            screenshotProtectionField = nil
        }

        // MARK: WKScriptMessageHandler
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "haptic" {
                handleHaptic(message: message)
            } else if message.name == "notifications" {
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                DispatchQueue.main.async { self.handleNotification(action: action, payload: body) }
            } else if message.name == "review" {
                DispatchQueue.main.async { self.requestAppReview() }
            } else if message.name == "openURL" {
                guard let body = message.body as? [String: Any],
                      let urlString = body["url"] as? String else { return }
                handleOpenExternalURL(urlString)
            } else if message.name == "icloud" {
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                if action == "save" {
                    // Save immediately (not async) to ensure data persists before app could be killed
                    self.saveToICloud(payload: body)
                }
            } else if message.name == "shareImage" {
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String,
                      let dataURL = body["dataURL"] as? String else { return }
                imageExporter.handle(action: action, dataURL: dataURL) { [weak self] outcome in
                    self?.reportPhotoSave(outcome)
                }
            } else if message.name == "openAppSettings" {
                handleOpenAppSettings()
            } else if message.name == "checkBoardUnlocked" {
                Task { @MainActor in
                    await BoardStore.shared.refresh()
                    self.boardEntitlementReporter.reportObservedEntitlement(
                        BoardStore.shared.isUnlocked
                    )
                    _ = try? await self.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardTrialCount(self.trialStore.currentCount())
                    )
                }
            } else if message.name == "boardTrial" {
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                let localCount = body["localCount"] as? Int ?? 0
                let updatedCount: Int
                if action == "increment" {
                    updatedCount = trialStore.increment(localCount: localCount)
                } else {
                    updatedCount = trialStore.sync(localCount: localCount)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardTrialCount(updatedCount),
                        completionHandler: nil
                    )
                }
            } else if message.name == "purchaseBoard" {
                Task { @MainActor in
                    let outcome = await BoardStore.shared.purchase()
                    _ = try? await self.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardPurchaseResult(outcome)
                    )
                }
            } else if message.name == "fetchBoardPrice" {
                Task { @MainActor in
                    let price = await BoardStore.shared.fetchDisplayPrice() ?? ""
                    _ = try? await self.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardPriceResult(price)
                    )
                }
            } else if message.name == "restorePurchases" {
                Task { @MainActor in
                    await self.boardEntitlementReporter.reportRestore(
                        performRestore: { await BoardStore.shared.restore() },
                        reportOutcome: { outcome in
                            _ = try await self.webView?.evaluateJavaScript(
                                BridgeJavaScript.boardRestoreResult(outcome)
                            )
                        }
                    )
                }
            } else if message.name == "photoSave" {
                guard let body = message.body as? [String: Any],
                      let filename = body["filename"] as? String,
                      let dataURL = body["dataURL"] as? String else { return }
                savePhoto(filename: filename, dataURL: dataURL)
            } else if message.name == "photoLoad" {
                guard let body = message.body as? [String: Any],
                      let reqId = body["reqId"] as? String,
                      let filename = body["filename"] as? String else { return }
                loadPhoto(reqId: reqId, filename: filename)
            } else if message.name == "photoGC" {
                guard let body = message.body as? [String: Any],
                      let keep = body["keep"] as? [String] else { return }
                DispatchQueue.global(qos: .background).async {
                    do {
                        try self.photoStore.garbageCollect(keeping: Set(keep))
                    } catch {
                        self.photoLogger.error(
                            "Photo garbage collection failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            } else if message.name == "migrationExport" {
                guard let body = message.body as? [String: Any],
                      let entriesJSON = body["entries"] as? String else { return }
                let deletedIDsJSON = body["deletedIDs"] as? String ?? "[]"
                handleMigrationExport(
                    entriesJSON: entriesJSON,
                    deletedIDsJSON: deletedIDsJSON
                )
            } else if message.name == "boardProtect" {
                let protect = message.body as? Bool ?? false
                DispatchQueue.main.async {
                    if protect { self.applyBoardProtection() }
                    else        { self.removeBoardProtection() }
                }
            } else if message.name == "cloudkit" {
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                if action == "push", let entryStr = body["entry"] as? String {
                    guard let photosDir = photosDirectory(),
                          let data = entryStr.data(using: .utf8),
                          let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
                    Task { @MainActor in
                        CloudKitSync.shared.pushEntry(entry, photosDir: photosDir)
                    }
                } else if action == "pushBatch", let entriesStr = body["entries"] as? String {
                    guard let photosDir = photosDirectory(),
                          let data = entriesStr.data(using: .utf8),
                          let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
                    Task { @MainActor in
                        CloudKitSync.shared.pushEntries(entries, photosDir: photosDir)
                    }
                } else if action == "delete", let id = body["id"] as? String {
                    let deletedAt = (body["deletedAt"] as? Double)
                        ?? (Date().timeIntervalSince1970 * 1000.0)
                    Task { @MainActor in
                        CloudKitSync.shared.deleteEntry(id: id, deletedAt: deletedAt)
                    }
                } else if action == "pull" {
                    guard let wv = webView else { return }
                    pullCloudKitData(into: wv)
                }
            }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialLoad = true
            // Force iCloud pull before injecting
            NSUbiquitousKeyValueStore.default.synchronize()
            // Page fully loaded — push any iCloud data into localStorage
            injectICloudData(into: webView)
            pullCloudKitData(into: webView)
            WebViewCoordinatorBridge.shared.flushPendingWatchEntries()
            WebViewCoordinatorBridge.shared.flushPendingDeepLink()
            let currentTrialCount = trialStore.currentCount()
            webView.evaluateJavaScript(
                BridgeJavaScript.boardTrialCount(currentTrialCount),
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showLoadError(error, in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showLoadError(error, in: webView)
        }

        private func showLoadError(_ error: Error, in webView: WKWebView) {
            let message = Self.escapeHTML(error.localizedDescription)
            webView.loadHTMLString(Self.errorHTML(title: "Clovery could not load", message: message), baseURL: nil)
        }

        static func errorHTML(title: String, message: String) -> String {
            """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
              <style>
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  background: #DDD7C9;
                  color: #1A2418;
                  font: -apple-system-body;
                }
                body {
                  box-sizing: border-box;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  padding: 28px;
                }
                main {
                  max-width: 320px;
                  padding: 20px;
                  border-radius: 18px;
                  background: rgba(250, 250, 246, 0.78);
                  box-shadow: 0 12px 28px rgba(49, 54, 43, 0.12);
                }
                h1 { margin: 0 0 10px; font-size: 20px; }
                p { margin: 0; line-height: 1.45; color: #5C6658; }
              </style>
            </head>
            <body>
              <main>
                <h1>\(escapeHTML(title))</h1>
                <p>\(message)</p>
              </main>
            </body>
            </html>
            """
        }

        private static func escapeHTML(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        // MARK: Haptic
        private func handleHaptic(message: WKScriptMessage) {
            guard let body = message.body as? [String: String] else { return }
            let type  = body["type"]  ?? "impact"
            let style = body["style"] ?? "medium"

            DispatchQueue.main.async {
                switch type {
                case "impact":
                    let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
                    switch style {
                    case "light":  feedbackStyle = .light
                    case "heavy":  feedbackStyle = .heavy
                    case "rigid":  feedbackStyle = .rigid
                    case "soft":   feedbackStyle = .soft
                    default:       feedbackStyle = .medium
                    }
                    let g = UIImpactFeedbackGenerator(style: feedbackStyle)
                    g.prepare(); g.impactOccurred()

                case "notification":
                    let feedbackType: UINotificationFeedbackGenerator.FeedbackType
                    switch style {
                    case "success": feedbackType = .success
                    case "warning": feedbackType = .warning
                    case "error":   feedbackType = .error
                    default:        feedbackType = .success
                    }
                    let g = UINotificationFeedbackGenerator()
                    g.prepare(); g.notificationOccurred(feedbackType)

                case "selection":
                    let g = UISelectionFeedbackGenerator()
                    g.prepare(); g.selectionChanged()

                default: break
                }
            }
        }

        // MARK: App Store Review & External Links
        private func requestAppReview() {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        }

        private func handleOpenExternalURL(_ urlString: String) {
            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http", "itms-apps"].contains(scheme) else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }

        private func reportPhotoSave(_ outcome: PhotoSaveOutcome) {
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(
                    BridgeJavaScript.photoSaveResult(outcome),
                    completionHandler: nil
                )
            }
        }

        func handleOpenAppSettings() {
            imageExporter.openSettings()
        }

        @MainActor
        func startObservingBoardStore() {
            guard boardEntitlementCancellable == nil else { return }
            boardEntitlementCancellable = BoardStore.shared.$isUnlocked
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] unlocked in
                    self?.boardEntitlementReporter.reportObservedEntitlement(unlocked)
                }
        }

        // MARK: iCloud Key-Value Sync

        func startObservingICloud() {
            let store = NSUbiquitousKeyValueStore.default
            store.synchronize()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(iCloudDataChanged(_:)),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store
            )

            // On fresh install, iCloud KV data may arrive AFTER didFinish.
            // Retry lightly to catch delayed KVS hydration while CloudKit remains primary.
            for delay in [1.0, 4.0, 12.0, 30.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, let wv = self.webView else { return }
                    store.synchronize()
                    self.injectICloudData(into: wv)
                }
            }
        }

        // Called when another device writes to iCloud KV store
        @objc private func iCloudDataChanged(_ notification: Notification) {
            guard let wv = webView else { return }
            DispatchQueue.main.async {
                self.injectICloudData(into: wv)
            }
        }

        // MARK: – Photo file storage
        private func photosDirectory() -> URL? {
            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
            let photosDir = dir.appendingPathComponent("photos", isDirectory: true)
            if !FileManager.default.fileExists(atPath: photosDir.path) {
                try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            }
            return photosDir
        }

        private func savePhoto(filename: String, dataURL: String) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    try photoStore.save(filename: filename, dataURL: dataURL)
                    evaluatePhotoJavaScript(BridgeJavaScript.photoSaved(filename: filename))
                } catch {
                    let code = (error as? PhotoStoreError)?.code ?? "ioError"
                    photoLogger.error(
                        "Photo save failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    evaluatePhotoJavaScript(
                        BridgeJavaScript.photoSaveFailed(filename: filename, code: code)
                    )
                }
            }
        }

        private func loadPhoto(reqId: String, filename: String) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let base64: String?
                do {
                    base64 = try photoStore.load(filename: filename)
                } catch {
                    base64 = nil
                    photoLogger.error(
                        "Photo load failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }

                evaluatePhotoJavaScript(
                    BridgeJavaScript.photoLoaded(reqId: reqId, base64: base64)
                )
            }
        }

        private func evaluatePhotoJavaScript(_ script: String) {
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        private func handleMigrationExport(entriesJSON: String, deletedIDsJSON: String) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    let result = try MigrationBundleExporter().export(
                        entriesJSON: entriesJSON,
                        deletedIDsJSON: deletedIDsJSON
                    )
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript(
                            BridgeJavaScript.migrationExportResult(
                                status: "success",
                                entryCount: result.entryCount,
                                photoCount: result.photoCount
                            ),
                            completionHandler: nil
                        )
                        self.presentMigrationArchive(result.archiveURL)
                    }
                } catch {
                    let errorCode = self.migrationExportErrorCode(error)
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript(
                            BridgeJavaScript.migrationExportResult(
                                status: "failed",
                                errorCode: errorCode
                            ),
                            completionHandler: nil
                        )
                    }
                }
            }
        }

        @MainActor
        private func presentMigrationArchive(_ archiveURL: URL) {
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?
                .rootViewController else {
                webView?.evaluateJavaScript(
                    BridgeJavaScript.migrationExportResult(
                        status: "failed",
                        errorCode: "shareUnavailable"
                    ),
                    completionHandler: nil
                )
                return
            }

            let activityController = UIActivityViewController(
                activityItems: [archiveURL],
                applicationActivities: nil
            )
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(
                    x: rootViewController.view.bounds.midX,
                    y: rootViewController.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            rootViewController.present(activityController, animated: true)
        }

        private func migrationExportErrorCode(_ error: Error) -> String {
            switch error {
            case MigrationBundleError.invalidEntriesJSON:
                "invalidEntries"
            case MigrationBundleError.invalidDeletedIDsJSON:
                "invalidDeletedIDs"
            case MigrationBundleError.invalidPhotoFilename:
                "invalidPhotoFilename"
            case MigrationBundleError.missingPhoto:
                "missingPhoto"
            case MigrationBundleError.photoHashMismatch,
                 MigrationBundleError.photoSizeMismatch:
                "photoVerificationFailed"
            default:
                "exportFailed"
            }
        }

        private func saveToICloud(payload: [String: Any]) {
            let store = NSUbiquitousKeyValueStore.default
            let entriesStr = payload["clovery_entries"] as? String
            let profileName = payload["clovery_name"] as? String
            let deletedMapStr = payload["deleted_map"] as? String

            if let entries = entriesStr {
                // Compress and save slim entries within Apple's 1MB KVS ceiling
                if let compressed = Self.boundedKVSCompressedEntries(from: entries) {
                    store.set(compressed, forKey: "clovery_entries_z")
                    store.removeObject(forKey: "clovery_entries")
                }
                if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let backupURL = dir.appendingPathComponent("clovery_backup.json")
                    var backup: [String: Any] = ["entries": entries]
                    if let name = profileName { backup["name"] = name }
                    if let deletedMapStr { backup["deletedMap"] = deletedMapStr }
                    backup["ts"] = Date().timeIntervalSince1970
                    if let data = try? JSONSerialization.data(withJSONObject: backup) {
                        try? data.write(to: backupURL, options: .atomic)
                    }
                }
            }
            // FULL local backup — includes photos & deletedMap for recovery
            if let fullEntries = payload["full_entries"] as? String,
               let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fullBackupURL = dir.appendingPathComponent("clovery_full_backup.json")
                var fullBackup: [String: Any] = ["entries": fullEntries]
                if let name = profileName { fullBackup["name"] = name }
                if let deletedMapStr { fullBackup["deletedMap"] = deletedMapStr }
                fullBackup["ts"] = Date().timeIntervalSince1970
                if let data = try? JSONSerialization.data(withJSONObject: fullBackup) {
                    do {
                        try data.write(to: fullBackupURL, options: .atomic)
                    } catch {
                        print("[Clovery iCloud] full backup write failed: \(error.localizedDescription)")
                    }
                }
            }
            if let name = profileName {
                store.set(name, forKey: "clovery_name")
            }
            if let lang = payload["widget_lang"] as? String {
                store.set(lang, forKey: "clovery_lang")
            }
            if let deletedMapStr,
               let delData = deletedMapStr.data(using: .utf8),
               let compressed = try? (delData as NSData).compressed(using: .zlib) as Data,
               compressed.count <= 120_000 {
                store.set(compressed, forKey: "clovery_deleted_map_z")
            }
            if let tweak = payload["clovery_tweak"] as? String {
                store.set(tweak, forKey: "clovery_tweak")
            }
            if let ts = payload["lastModified"] as? Double {
                store.set(ts, forKey: "clovery_lastModified")
            }
            store.synchronize()

            let font = payload["widget_font"] as? String ?? "Gaegu"
            let palette = payload["widget_palette"] as? String ?? "clover"
            let lang = payload["widget_lang"] as? String ?? "zh"
            let dark: Bool = {
                if let b = payload["widget_dark"] as? Bool { return b }
                if let s = payload["widget_dark"] as? String { return s == "true" || s == "1" }
                return false
            }()

            // ── Write to App Groups shared container for Widget Extension ──
            if let shared = UserDefaults(suiteName: "group.com.clovery.app") {
                if let entries = entriesStr {
                    shared.set(entries, forKey: "widget_entries")
                }
                if let name = profileName {
                    shared.set(name, forKey: "widget_name")
                }
                if let ts = payload["lastModified"] as? Double {
                    shared.set(ts, forKey: "widget_lastModified")
                }
                shared.set(font, forKey: "widget_font")
                shared.set(palette, forKey: "widget_palette")
                shared.set(lang, forKey: "widget_lang")
                shared.set(dark, forKey: "widget_dark")
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }

            if let entries = entriesStr {
                Task { @MainActor in
                    WatchSessionManager.shared.updateSnapshot(
                        entriesJSON: entries,
                        name: profileName ?? "",
                        palette: palette,
                        lang: lang,
                        dark: dark
                    )
                }
            }
        }

        private static func boundedKVSCompressedEntries(from entriesJSON: String, limitBytes: Int = 750_000) -> Data? {
            if let rawData = entriesJSON.data(using: .utf8),
               let compressed = try? (rawData as NSData).compressed(using: .zlib) as Data,
               compressed.count <= limitBytes {
                return compressed
            }
            guard let rawData = entriesJSON.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: rawData)) as? [[String: Any]],
                  !arr.isEmpty else {
                return nil
            }
            // Keep newest entries that fit comfortably under the 1MB KVS ceiling
            var count = max(1, arr.count / 2)
            while count >= 1 {
                let slice = Array(arr.prefix(count))
                if let sliceData = try? JSONSerialization.data(withJSONObject: slice),
                   let compressed = try? (sliceData as NSData).compressed(using: .zlib) as Data,
                   compressed.count <= limitBytes {
                    return compressed
                }
                if count == 1 { break }
                count = max(1, count / 2)
            }
            return nil
        }

        private static func mergeDeletedMapJSON(local: String?, remote: String?) -> String? {
            var merged: [String: Double] = [:]
            for raw in [local, remote] {
                guard let raw,
                      let data = raw.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                for (id, value) in dict {
                    let ts = (value as? NSNumber)?.doubleValue ?? 0
                    if let prev = merged[id] {
                        if ts > prev { merged[id] = ts }
                    } else {
                        merged[id] = ts
                    }
                }
            }
            guard !merged.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: merged),
                  let str = String(data: data, encoding: .utf8) else { return local ?? remote }
            return str
        }

        // Merges two entries-JSON strings by id + updatedAt: keeps local full
        // entries (with photos) as base and appends/updates entries from `additions`.
        private func mergeEntriesJSON(base: String?, additions: String?) -> String? {
            guard let baseStr = base,
                  let baseData = baseStr.data(using: .utf8),
                  let baseArr = (try? JSONSerialization.jsonObject(with: baseData)) as? [[String: Any]] else {
                return additions ?? base
            }
            guard let addStr = additions,
                  let addData = addStr.data(using: .utf8),
                  let addArr = (try? JSONSerialization.jsonObject(with: addData)) as? [[String: Any]] else {
                return base
            }
            var byId: [String: Int] = [:]
            var merged = baseArr
            for (idx, e) in merged.enumerated() {
                if let id = e["id"] as? String { byId[id] = idx }
            }
            var changed = false
            for e in addArr {
                guard let id = e["id"] as? String else { continue }
                if let idx = byId[id] {
                    let localEntry = merged[idx]
                    let localTime = (localEntry["updatedAt"] as? Double) ?? (localEntry["createdAt"] as? Double) ?? 0
                    let addTime = (e["updatedAt"] as? Double) ?? (e["createdAt"] as? Double) ?? 0
                    if addTime > localTime {
                        var updated = e
                        if updated["photos"] == nil, let localPhotos = localEntry["photos"] {
                            updated["photos"] = localPhotos
                        }
                        merged[idx] = updated
                        changed = true
                    }
                } else {
                    byId[id] = merged.count
                    merged.append(e)
                    changed = true
                }
            }
            guard changed,
                  let mergedData = try? JSONSerialization.data(withJSONObject: merged),
                  let mergedStr = String(data: mergedData, encoding: .utf8) else { return base }
            return mergedStr
        }

        // Swift → JS: push iCloud/local data into the running WebView
        private func injectICloudData(into webView: WKWebView) {
            let store = NSUbiquitousKeyValueStore.default
            var name: String? = store.string(forKey: "clovery_name")
            var deletedMapStr: String? = nil

            var fullBackupEntries: String? = nil
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fullBackupURL = dir.appendingPathComponent("clovery_full_backup.json")
                if let data = try? Data(contentsOf: fullBackupURL),
                   let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    fullBackupEntries = backup["entries"] as? String
                    deletedMapStr = backup["deletedMap"] as? String
                    if name == nil { name = backup["name"] as? String }
                }
            }

            var kvEntries: String? = nil
            if let compressed = store.data(forKey: "clovery_entries_z") {
                if let decompressed = try? (compressed as NSData).decompressed(using: .zlib) as Data,
                   let str = String(data: decompressed, encoding: .utf8) {
                    kvEntries = str
                }
            }
            if kvEntries == nil {
                kvEntries = store.string(forKey: "clovery_entries")
            }

            var entries = mergeEntriesJSON(base: fullBackupEntries, additions: kvEntries)

            if entries == nil {
                if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let backupURL = dir.appendingPathComponent("clovery_backup.json")
                    if let data = try? Data(contentsOf: backupURL),
                       let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        entries = backup["entries"] as? String
                        if deletedMapStr == nil { deletedMapStr = backup["deletedMap"] as? String }
                        if name == nil { name = backup["name"] as? String }
                    }
                }
            }

            var kvDeletedMapStr: String? = nil
            if let delCompressed = store.data(forKey: "clovery_deleted_map_z"),
               let delData = try? (delCompressed as NSData).decompressed(using: .zlib) as Data,
               let str = String(data: delData, encoding: .utf8) {
                kvDeletedMapStr = str
            }
            let mergedDeletedMapStr = Self.mergeDeletedMapJSON(local: deletedMapStr, remote: kvDeletedMapStr)

            var dataObj: [String: Any] = ["source": "kv"]
            if let entries = entries { dataObj["entries"] = entries }
            if let name = name { dataObj["clovery_name"] = name }
            if let mergedDeletedMapStr { dataObj["deleted_map"] = mergedDeletedMapStr }
            if let lang = store.string(forKey: "clovery_lang") { dataObj["clovery_lang"] = lang }
            if let tweak = store.string(forKey: "clovery_tweak") { dataObj["clovery_tweak"] = tweak }

            guard dataObj["entries"] != nil || dataObj["clovery_name"] != nil || dataObj["deleted_map"] != nil else { return }

            let js = BridgeJavaScript.iCloudData(dataObj)
            guard !js.isEmpty else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Pulls all pages from CloudKit (entries + photos + tombstones) and pushes
        // both merged payloads and live status updates into the running WebView.
        func pullCloudKitData(into webView: WKWebView, completion: (() -> Void)? = nil) {
            guard !isCloudKitPulling else {
                completion?()
                return
            }
            guard let photosDir = photosDirectory() else {
                completion?()
                return
            }
            isCloudKitPulling = true
            let syncingScript = BridgeJavaScript.cloudKitSyncStatus([
                "state": CloudKitSyncStatusState.syncing.rawValue,
            ])
            DispatchQueue.main.async {
                webView.evaluateJavaScript(syncingScript, completionHandler: nil)
            }

            CloudKitSync.shared.pullAllWithStatus(photosDir: photosDir) { [weak self] result in
                defer {
                    self?.isCloudKitPulling = false
                    completion?()
                }
                var statusPayload: [String: Any] = [
                    "state": result.status.rawValue,
                    "entryCount": result.entries.count,
                ]
                if result.status == .synced {
                    statusPayload["syncedAt"] = Date().timeIntervalSince1970 * 1000.0
                }
                if let errorMessage = result.errorMessage {
                    statusPayload["error"] = errorMessage
                }
                let statusScript = BridgeJavaScript.cloudKitSyncStatus(statusPayload)
                DispatchQueue.main.async {
                    webView.evaluateJavaScript(statusScript, completionHandler: nil)
                }

                if result.status == .synced || !result.entries.isEmpty {
                    let entriesData = (try? JSONSerialization.data(withJSONObject: result.entries))
                        ?? Data("[]".utf8)
                    let entriesStr = String(data: entriesData, encoding: .utf8) ?? "[]"
                    let dataObj: [String: Any] = [
                        "entries": entriesStr,
                        "source": "cloudkit",
                    ]
                    let js = BridgeJavaScript.iCloudData(dataObj)
                    if !js.isEmpty {
                        DispatchQueue.main.async {
                            webView.evaluateJavaScript(js, completionHandler: nil)
                        }
                    }
                }
            }
        }

        // MARK: Notifications
        private func handleNotification(action: String, payload: [String: Any]) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self

            switch action {
            case "scheduleDaily":
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.scheduleDaily(payload: payload)
                }

            case "cancelDaily":
                center.removePendingNotificationRequests(withIdentifiers: ["clovery-daily"])

            case "scheduleWeekly":
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.scheduleWeekly(payload: payload)
                }

            case "cancelWeekly":
                center.removePendingNotificationRequests(withIdentifiers: ["clovery-weekly"])

            default: break
            }
        }

        private func scheduleDaily(payload: [String: Any]) {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["clovery-daily"])

            let content = UNMutableNotificationContent()
            content.title = payload["title"] as? String ?? "Time to journal 🍀"
            content.body  = payload["body"]  as? String ?? "What's your lucky thing today?"
            content.sound = .default

            var dc = DateComponents()
            dc.hour   = payload["hour"]   as? Int ?? 21
            dc.minute = payload["minute"] as? Int ?? 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let request = UNNotificationRequest(identifier: "clovery-daily",
                                               content: content, trigger: trigger)
            center.add(request)
        }

        private func scheduleWeekly(payload: [String: Any]) {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["clovery-weekly"])

            let content = UNMutableNotificationContent()
            content.title = payload["title"] as? String ?? "Weekly recap 🍀"
            content.body  = payload["body"]  as? String ?? "Look back at your week's lucky moments"
            content.sound = .default

            var dc = DateComponents()
            dc.weekday = 1   // Sunday
            dc.hour    = 20
            dc.minute  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let request = UNNotificationRequest(identifier: "clovery-weekly",
                                               content: content, trigger: trigger)
            center.add(request)
        }

        // MARK: UNUserNotificationCenterDelegate
        // Show notification even when app is in foreground
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Register message handlers
        config.userContentController.add(context.coordinator, name: "haptic")
        config.userContentController.add(context.coordinator, name: "notifications")
        config.userContentController.add(context.coordinator, name: "review")
        config.userContentController.add(context.coordinator, name: "openURL")
        config.userContentController.add(context.coordinator, name: "icloud")
        config.userContentController.add(context.coordinator, name: "shareImage")
        config.userContentController.add(context.coordinator, name: "openAppSettings")
        config.userContentController.add(context.coordinator, name: "checkBoardUnlocked")
        config.userContentController.add(context.coordinator, name: "boardTrial")
        config.userContentController.add(context.coordinator, name: "purchaseBoard")
        config.userContentController.add(context.coordinator, name: "fetchBoardPrice")
        config.userContentController.add(context.coordinator, name: "restorePurchases")
        config.userContentController.add(context.coordinator, name: "photoSave")
        config.userContentController.add(context.coordinator, name: "photoLoad")
        config.userContentController.add(context.coordinator, name: "photoGC")
        config.userContentController.add(context.coordinator, name: "migrationExport")
        config.userContentController.add(context.coordinator, name: "cloudkit")
        config.userContentController.add(context.coordinator, name: "boardProtect")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 221/255, green: 215/255, blue: 201/255, alpha: 1)

        // Wire up iCloud sync
        context.coordinator.webView = webView
        context.coordinator.startObservingBoardStore()
        context.coordinator.startObservingICloud()
        WebViewCoordinatorBridge.shared.coordinator = context.coordinator

        if let url = Bundle.main.url(forResource: "Clover Diary", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = Coordinator.errorHTML(
                title: "Clovery could not load",
                message: "Clover Diary.html was not found in the app bundle."
            )
            webView.loadHTMLString(html, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// Lets AppDelegate / SwiftUI Scene reach the running WebView's Coordinator
// for CloudKit silent push, foreground refresh, deep links, and Watch entries.
@MainActor
class WebViewCoordinatorBridge {
    static let shared = WebViewCoordinatorBridge()
    weak var coordinator: WebView.Coordinator?
    private var pendingDeepLink: String?

    func refreshBoardEntitlement() {
        Task { @MainActor in
            await BoardStore.shared.refresh()
        }
    }

    func refreshICloudSync() {
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let coordinator, let webView = coordinator.webView, coordinator.didFinishInitialLoad else {
            return
        }
        coordinator.pullCloudKitData(into: webView)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "clovery" else { return }
        let rawRoute = (url.host ?? "") + url.path
        let route = rawRoute.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !route.isEmpty else { return }
        pendingDeepLink = route
        flushPendingDeepLink()
    }

    func flushPendingDeepLink() {
        guard let route = pendingDeepLink,
              let coordinator,
              coordinator.didFinishInitialLoad,
              let webView = coordinator.webView else { return }
        pendingDeepLink = nil
        webView.evaluateJavaScript(BridgeJavaScript.deepLink(route), completionHandler: nil)
    }

    func flushPendingWatchEntries() {
        let pending = WatchSessionManager.shared.pendingEntries()
        guard !pending.isEmpty else { return }
        deliverWatchEntries(pending)
    }

    func deliverWatchEntries(_ entries: [[String: Any]]) {
        guard !entries.isEmpty,
              let coordinator,
              coordinator.didFinishInitialLoad,
              let webView = coordinator.webView else { return }
        let ids = entries.compactMap { $0["id"] as? String }
        let script = BridgeJavaScript.watchEntries(entries)
        webView.evaluateJavaScript(script) { _, error in
            if error == nil {
                Task { @MainActor in
                    WatchSessionManager.shared.clearPendingEntries(ids: ids)
                }
            }
        }
    }

    func handleRemoteCloudKitNotification(completion: @escaping () -> Void) {
        if let coordinator, let webView = coordinator.webView {
            coordinator.pullCloudKitData(into: webView, completion: completion)
            return
        }
        // Background wakeup without a live WebView: still refresh App Group widget snapshot.
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion()
            return
        }
        let photosDir = docsDir.appendingPathComponent("photos", isDirectory: true)
        CloudKitSync.shared.pullAllWithStatus(photosDir: photosDir) { result in
            defer { completion() }
            guard !result.entries.isEmpty,
                  let shared = UserDefaults(suiteName: "group.com.clovery.app") else { return }
            let existingRaw = shared.string(forKey: "widget_entries") ?? "[]"
            var existing = (try? JSONSerialization.jsonObject(with: Data(existingRaw.utf8))) as? [[String: Any]] ?? []
            var byId = Dictionary(uniqueKeysWithValues: existing.enumerated().compactMap { idx, e in
                (e["id"] as? String).map { ($0, idx) }
            })
            var deletedIDs = Set<String>()
            for remote in result.entries {
                guard let id = remote["id"] as? String else { continue }
                if (remote["isDeleted"] as? Bool) == true {
                    deletedIDs.insert(id)
                    continue
                }
                if let idx = byId[id] {
                    let localTime = (existing[idx]["updatedAt"] as? Double) ?? (existing[idx]["createdAt"] as? Double) ?? 0
                    let remoteTime = (remote["updatedAt"] as? Double) ?? (remote["createdAt"] as? Double) ?? 0
                    if remoteTime > localTime {
                        existing[idx] = remote
                    }
                } else {
                    byId[id] = existing.count
                    existing.append(remote)
                }
            }
            if !deletedIDs.isEmpty {
                existing.removeAll { ($0["id"] as? String).map { deletedIDs.contains($0) } ?? false }
            }
            let slimForWidget: [[String: Any]] = existing.map { entry in
                var copy = entry
                copy.removeValue(forKey: "photos")
                copy.removeValue(forKey: "text")
                return copy
            }
            if let data = try? JSONSerialization.data(withJSONObject: slimForWidget),
               let json = String(data: data, encoding: .utf8) {
                shared.set(json, forKey: "widget_entries")
                WidgetCenter.shared.reloadAllTimelines()
                let palette = shared.string(forKey: "widget_palette") ?? "clover"
                let lang = shared.string(forKey: "widget_lang") ?? "zh"
                let dark = shared.bool(forKey: "widget_dark")
                let name = shared.string(forKey: "widget_name") ?? ""
                Task { @MainActor in
                    WatchSessionManager.shared.updateSnapshot(
                        entriesJSON: json,
                        name: name,
                        palette: palette,
                        lang: lang,
                        dark: dark
                    )
                }
            }
        }
    }
}
