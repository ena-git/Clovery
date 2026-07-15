import SwiftUI
import WebKit
import UIKit
import UserNotifications
import StoreKit
import Photos
import WidgetKit
import OSLog

struct WebView: UIViewRepresentable {

    // MARK: – Message handler (haptic + notifications + iCloud)
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UNUserNotificationCenterDelegate {

        // Weak ref so we can push iCloud data into the running WebView
        weak var webView: WKWebView?
        private let photoLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.clovery.app",
            category: "Photos"
        )
        private let photoStore: PhotoStoring

        init(photoStore: PhotoStoring = PhotoStore()) {
            self.photoStore = photoStore
            super.init()
        }

        // MARK: Screenshot protection (UITextField isSecureTextEntry trick)
        private var screenshotProtectionField: UITextField?

        @MainActor
        private func applyBoardProtection() {
            guard let wv = webView,
                  let parent = wv.superview,
                  screenshotProtectionField == nil else { return }
            let tf = UITextField()
            tf.isSecureTextEntry = true
            tf.backgroundColor = .clear
            tf.frame = wv.frame
            tf.autoresizingMask = wv.autoresizingMask
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
            wv.autoresizingMask = tf.autoresizingMask
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
                DispatchQueue.main.async { self.handleShareImage(action: action, dataURL: dataURL) }
            } else if message.name == "checkBoardUnlocked" {
                Task { @MainActor in
                    await BoardStore.shared.refresh()
                    let unlocked = BoardStore.shared.isUnlocked
                    _ = try? await self.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardUnlockStatus(unlocked)
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
                    await BoardStore.shared.restore()
                    let unlocked = BoardStore.shared.isUnlocked
                    _ = try? await self.webView?.evaluateJavaScript(
                        BridgeJavaScript.boardUnlockStatus(unlocked)
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
                } else if action == "pull" {
                    guard let wv = webView else { return }
                    pullCloudKitData(into: wv)
                }
            }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Force iCloud pull before injecting
            NSUbiquitousKeyValueStore.default.synchronize()
            // Page fully loaded — push any iCloud data into localStorage
            injectICloudData(into: webView)
            pullCloudKitData(into: webView)
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

        // MARK: App Store Review
        private func requestAppReview() {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        }

        // MARK: Share Image
        private func handleShareImage(action: String, dataURL: String) {
            let prefix = "data:image/png;base64,"
            guard dataURL.hasPrefix(prefix),
                  let imageData = Data(base64Encoded: String(dataURL.dropFirst(prefix.count))),
                  let image = UIImage(data: imageData) else {
                if action == "save" {
                    reportPhotoSave(.invalidImage)
                }
                return
            }

            switch action {
            case "save":
                saveImageDataToPhotos(imageData)
            case "share":
                // Write to a temp PNG file so WeChat (and other apps) can receive it correctly.
                // Passing UIImage directly causes "发送异常" in WeChat's share extension.
                let tempURL: URL = {
                    let name = "clovery_\(Int(Date().timeIntervalSince1970)).png"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try? image.pngData()?.write(to: url)
                    return url
                }()
                let vc = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    vc.popoverPresentationController?.sourceView = rootVC.view
                    rootVC.present(vc, animated: true)
                }
            default: break
            }
        }

        private func saveImageDataToPhotos(_ imageData: Data) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                guard let self else { return }

                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, data: imageData, options: nil)
                    } completionHandler: { success, error in
                        if success {
                            self.reportPhotoSave(.success)
                        } else {
                            self.photoLogger.error(
                                "Photo save failed: \(error?.localizedDescription ?? "unknown error", privacy: .public)"
                            )
                            self.reportPhotoSave(.failed)
                        }
                    }
                case .denied, .restricted:
                    self.photoLogger.error("Photo add permission denied")
                    self.reportPhotoSave(.permissionDenied)
                case .notDetermined:
                    self.photoLogger.error("Photo add permission remained undetermined")
                    self.reportPhotoSave(.failed)
                @unknown default:
                    self.photoLogger.error("Unknown photo authorization status")
                    self.reportPhotoSave(.failed)
                }
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

            // On fresh install, iCloud data may arrive AFTER didFinish.
            // Retry injection aggressively to catch late-arriving data.
            for delay in [0.5, 1.5, 3.0, 6.0, 12.0, 20.0, 30.0, 60.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, let wv = self.webView else { return }
                    store.synchronize()
                    let hasData = store.data(forKey: "clovery_entries_z") != nil || store.string(forKey: "clovery_entries") != nil
                    print("[Clovery iCloud] retry at \(delay)s — data exists: \(hasData)")
                    self.injectICloudData(into: wv)
                }
            }
        }

        // Called when another device writes to iCloud KV store
        @objc private func iCloudDataChanged(_ notification: Notification) {
            guard let wv = webView else { return }
            DispatchQueue.main.async { self.injectICloudData(into: wv) }
        }

        // JS → Swift: save to iCloud KV store (compressed, no photos) + full local backup (with photos)
        // MARK: – Photo file storage
        // Photos are stored as individual files in Documents/photos/ rather than
        // inline base64 inside the entries JSON, so saving/backing-up an entry
        // doesn't require re-serializing every historical photo every time.
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
            activityController.popoverPresentationController?.sourceView = rootViewController.view
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
            if let entries = payload["clovery_entries"] as? String {
                // Compress and save to KV store (slim — photos already stripped by JS)
                if let rawData = entries.data(using: .utf8),
                   let compressed = try? (rawData as NSData).compressed(using: .zlib) as Data {
                    print("[Clovery iCloud] entries: \(rawData.count) → compressed: \(compressed.count) bytes")
                    store.set(compressed, forKey: "clovery_entries_z")
                    store.removeObject(forKey: "clovery_entries")
                }
                // Legacy slim backup (kept for backward compatibility / migration)
                if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let backupURL = dir.appendingPathComponent("clovery_backup.json")
                    var backup: [String: Any] = ["entries": entries]
                    if let name = payload["clovery_name"] as? String { backup["name"] = name }
                    backup["ts"] = Date().timeIntervalSince1970
                    if let data = try? JSONSerialization.data(withJSONObject: backup) {
                        try? data.write(to: backupURL, options: .atomic)
                    }
                }
            }
            // FULL local backup — includes photos. This is the primary recovery
            // source if localStorage is ever wiped (iOS storage pressure, quota
            // errors, etc). Never sent to iCloud — Documents dir has no 1MB cap.
            if let fullEntries = payload["full_entries"] as? String,
               let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fullBackupURL = dir.appendingPathComponent("clovery_full_backup.json")
                var fullBackup: [String: Any] = ["entries": fullEntries]
                if let name = payload["clovery_name"] as? String { fullBackup["name"] = name }
                fullBackup["ts"] = Date().timeIntervalSince1970
                if let data = try? JSONSerialization.data(withJSONObject: fullBackup) {
                    do {
                        try data.write(to: fullBackupURL, options: .atomic)
                    } catch {
                        print("[Clovery iCloud] full backup write failed: \(error.localizedDescription)")
                    }
                }
            }
            if let name = payload["clovery_name"] as? String {
                store.set(name, forKey: "clovery_name")
            }
            if let ts = payload["lastModified"] as? Double {
                store.set(ts, forKey: "clovery_lastModified")
            }
            store.synchronize()

            // ── Write to App Groups shared container for Widget Extension ──
            if let shared = UserDefaults(suiteName: "group.com.clovery.app") {
                if let entries = payload["clovery_entries"] as? String {
                    shared.set(entries, forKey: "widget_entries")
                }
                if let name = payload["clovery_name"] as? String {
                    shared.set(name, forKey: "widget_name")
                }
                if let ts = payload["lastModified"] as? Double {
                    shared.set(ts, forKey: "widget_lastModified")
                }
                if let font = payload["widget_font"] as? String {
                    shared.set(font, forKey: "widget_font")
                }
                if let palette = payload["widget_palette"] as? String {
                    shared.set(palette, forKey: "widget_palette")
                }
                if let lang = payload["widget_lang"] as? String {
                    shared.set(lang, forKey: "widget_lang")
                }
                // Notify WidgetKit to refresh
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }

        // Merges two entries-JSON strings by id: every entry in `base` is kept as-is
        // (so `base`'s photos are never dropped), and any entry present in
        // `additions` but missing from `base` gets appended. Used to combine the
        // FULL local backup (has photos, but only this device's own writes) with
        // the iCloud KV store (no photos, but reflects writes from OTHER devices)
        // without either source blocking the other.
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
            var seenIds = Set<String>()
            for e in baseArr { if let id = e["id"] as? String { seenIds.insert(id) } }
            var merged = baseArr
            for e in addArr {
                guard let id = e["id"] as? String, !seenIds.contains(id) else { continue }
                merged.append(e)
                seenIds.insert(id)
            }
            guard merged.count > baseArr.count,
                  let mergedData = try? JSONSerialization.data(withJSONObject: merged),
                  let mergedStr = String(data: mergedData, encoding: .utf8) else { return base }
            return mergedStr
        }

        // Swift → JS: push iCloud/local data into the running WebView
        private func injectICloudData(into webView: WKWebView) {
            let store = NSUbiquitousKeyValueStore.default
            var name: String? = store.string(forKey: "clovery_name")

            // A. FULL local backup (has photos, but only reflects THIS device's own
            // writes) — used as the base so photos are never dropped, and as the
            // recovery source if localStorage on this device is ever wiped.
            var fullBackupEntries: String? = nil
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fullBackupURL = dir.appendingPathComponent("clovery_full_backup.json")
                if let data = try? Data(contentsOf: fullBackupURL),
                   let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    fullBackupEntries = backup["entries"] as? String
                    if name == nil { name = backup["name"] as? String }
                }
            }

            // B. iCloud KV store (slim, no photos) — the actual cross-device sync
            // channel. Reflects entries written by OTHER devices.
            var kvEntries: String? = nil
            if let compressed = store.data(forKey: "clovery_entries_z") {
                if let decompressed = try? (compressed as NSData).decompressed(using: .zlib) as Data,
                   let str = String(data: decompressed, encoding: .utf8) {
                    kvEntries = str
                    print("[Clovery iCloud] loaded compressed: \(compressed.count) → \(decompressed.count) bytes")
                }
            }
            if kvEntries == nil {
                kvEntries = store.string(forKey: "clovery_entries")
                if kvEntries != nil { print("[Clovery iCloud] loaded uncompressed") }
            }

            // Merge: full backup stays the base (keeps photos), KV store only adds
            // entries this device doesn't have yet (cross-device sync), never
            // overwrites or blocks it.
            var entries = mergeEntriesJSON(base: fullBackupEntries, additions: kvEntries)
            if entries != nil { print("[Clovery iCloud] merged local backup + KV store") }

            // Fallback: legacy slim local backup (no photos), only if nothing else exists
            if entries == nil {
                if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let backupURL = dir.appendingPathComponent("clovery_backup.json")
                    if let data = try? Data(contentsOf: backupURL),
                       let backup = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        entries = backup["entries"] as? String
                        if name == nil { name = backup["name"] as? String }
                        if entries != nil { print("[Clovery iCloud] loaded from legacy local backup") }
                    }
                }
            }

            guard let entries = entries else { return }

            var dataObj: [String: Any] = ["entries": entries]
            if let name = name {
                dataObj["clovery_name"] = name
            }

            let js = BridgeJavaScript.iCloudData(dataObj)
            guard !js.isEmpty else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Pulls every DiaryEntry record from CloudKit (text + photos) and merges
        // it into the running WebView via the same JS merge path the iCloud KV
        // store uses — mergeEntries() only ever ADDS what's missing locally.
        func pullCloudKitData(into webView: WKWebView, completion: (() -> Void)? = nil) {
            guard let photosDir = photosDirectory() else { completion?(); return }
            CloudKitSync.shared.pullAll(photosDir: photosDir) { entries in
                defer { completion?() }
                guard !entries.isEmpty,
                      let entriesData = try? JSONSerialization.data(withJSONObject: entries),
                      let entriesStr = String(data: entriesData, encoding: .utf8) else { return }
                let dataObj: [String: Any] = ["entries": entriesStr]
                let js = BridgeJavaScript.iCloudData(dataObj)
                guard !js.isEmpty else { return }
                webView.evaluateJavaScript(js, completionHandler: nil)
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
        config.userContentController.add(context.coordinator, name: "icloud")
        config.userContentController.add(context.coordinator, name: "shareImage")
        config.userContentController.add(context.coordinator, name: "checkBoardUnlocked")
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
        // Disable pinch-to-zoom so the app never scales like a webpage.
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        // Prevent UIScrollView from adding automatic safe-area insets,
        // which would cause a gap at the bottom of the screen.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Keep opaque so the background colour shows immediately on launch
        // (avoids the white flash before React finishes rendering).
        webView.isOpaque = true
        // Match app background colour #DDD7C9
        webView.backgroundColor = UIColor(red: 221/255, green: 215/255, blue: 201/255, alpha: 1)

        // Wire up iCloud sync
        context.coordinator.webView = webView
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

// Lets AppDelegate reach the running WebView's Coordinator (which it has no
// direct reference to) when a CloudKit silent push notification arrives.
@MainActor
class WebViewCoordinatorBridge {
    static let shared = WebViewCoordinatorBridge()
    weak var coordinator: WebView.Coordinator?

    func handleRemoteCloudKitNotification(completion: @escaping () -> Void) {
        guard let coordinator = coordinator, let webView = coordinator.webView else {
            completion()
            return
        }
        coordinator.pullCloudKitData(into: webView, completion: completion)
    }
}
