import Foundation
#if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

/// Keeps the Apple Watch app in sync with the diary that lives inside the web view.
///
/// iPhone → Watch: every time the web app saves, the latest entries plus the user's theme / font /
/// dark-mode / language choices are pushed as an application context.
/// Watch → iPhone: entries written on the watch arrive as user-info transfers, are parked in
/// UserDefaults until the web app is ready, then injected through `window.__clovery_addExternalEntry`.
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private let pendingKey = "watch_pending_entries"
    private let contextKey = "watch_last_context"
    private var flushing = false

    // MARK: - Public

    func activate() {
        #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    /// Called whenever the web app saves (see `writeWidgetSnapshot`).
    func push(payload: [String: Any]) {
        #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
        guard WCSession.isSupported() else { return }
        let shared = UserDefaults(suiteName: "group.com.clovery.app")
        var ctx: [String: Any] = [:]

        if let raw = payload["clovery_entries"] as? String,
           let data = raw.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let slim: [[String: Any]] = list
                .filter { ($0["isWelcome"] as? Bool) != true }
                .compactMap { e in
                    guard let id = e["id"] as? String, let date = e["date"] as? String,
                          let lucky = (e["lucky"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !lucky.isEmpty else { return nil }
                    var out: [String: Any] = ["id": id, "date": date, "lucky": String(lucky.prefix(600))]
                    if let m = e["mood"] as? String { out["mood"] = m }
                    if let c = e["createdAt"] as? Double { out["createdAt"] = c }
                    if let t = e["tags"] as? [String], !t.isEmpty { out["tags"] = t }
                    return out
                }
                .sorted {
                    let d0 = $0["date"] as? String ?? "", d1 = $1["date"] as? String ?? ""
                    if d0 != d1 { return d0 > d1 }
                    return ($0["createdAt"] as? Double ?? 0) > ($1["createdAt"] as? Double ?? 0)
                }
            let recent = Array(slim.prefix(60))
            if let d = try? JSONSerialization.data(withJSONObject: recent), let s = String(data: d, encoding: .utf8) {
                ctx["entries"] = s
            }
        }
        // Same sources the iPhone widget reads, so watch / widget / app always agree.
        ctx["font"] = shared?.string(forKey: "clovery_font_selection") ?? (payload["widget_font"] as? String) ?? "Gaegu"
        ctx["palette"] = (payload["widget_palette"] as? String) ?? shared?.string(forKey: "widget_palette") ?? "clover"
        ctx["lang"] = (payload["widget_lang"] as? String) ?? shared?.string(forKey: "widget_lang") ?? "zh"
        ctx["dark"] = (payload["widget_dark"] as? String) ?? shared?.string(forKey: "widget_dark") ?? "auto"
        if let name = payload["clovery_name"] as? String { ctx["name"] = name }

        UserDefaults.standard.set(ctx, forKey: contextKey)
        send(context: ctx)
        #endif
    }

    /// Injects any entries written on the watch into the web app. Safe to call at any time.
    func flushPending() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.flushing else { return }
            guard let webView = WebViewCoordinatorBridge.shared.coordinator?.webView else { return }
            var pending = self.loadPending()
            guard !pending.isEmpty else { return }
            self.flushing = true
            let batch = pending
            let group = DispatchGroup()
            for entry in batch {
                guard let id = entry["id"] as? String,
                      let script = BridgeJavaScript.addExternalEntry(entry) else { continue }
                group.enter()
                webView.evaluateJavaScript(script) { result, error in
                    if (result as? Bool) == true || (result as? NSNumber)?.boolValue == true {
                        pending.removeAll { ($0["id"] as? String) == id }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [weak self] in
                self?.savePending(pending)
                self?.flushing = false
            }
        }
    }

    // MARK: - Pending queue

    private func loadPending() -> [[String: Any]] {
        (UserDefaults.standard.array(forKey: pendingKey) as? [[String: Any]]) ?? []
    }
    private func savePending(_ list: [[String: Any]]) {
        UserDefaults.standard.set(list, forKey: pendingKey)
    }
    fileprivate func enqueue(_ info: [String: Any]) {
        guard let id = info["id"] as? String,
              let lucky = (info["lucky"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !lucky.isEmpty else { return }
        var list = loadPending()
        guard !list.contains(where: { ($0["id"] as? String) == id }) else { return }
        list.append([
            "id": id,
            "date": (info["date"] as? String) ?? Self.today(),
            "createdAt": (info["createdAt"] as? Double) ?? (Date().timeIntervalSince1970 * 1000).rounded(),
            "lucky": lucky,
            "mood": (info["mood"] as? String) ?? "lucky",
            "tags": [String](),
        ])
        savePending(list)
    }
    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: Date())
    }

    #if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
    fileprivate func send(context: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if NSDictionary(dictionary: session.applicationContext).isEqual(to: context) { return }
        try? session.updateApplicationContext(context)
    }
    #endif
}

#if canImport(WatchConnectivity) && !targetEnvironment(macCatalyst)
extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let ctx = UserDefaults.standard.dictionary(forKey: contextKey) { send(context: ctx) }
        flushPending()
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) {
        if let ctx = UserDefaults.standard.dictionary(forKey: contextKey) { send(context: ctx) }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard (userInfo["type"] as? String) == "newEntry" else { return }
        enqueue(userInfo)
        flushPending()
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard (message["type"] as? String) == "newEntry" else { return }
        enqueue(message)
        flushPending()
    }
}
#endif
