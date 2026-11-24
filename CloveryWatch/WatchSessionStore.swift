import Foundation
import WatchConnectivity
import Combine

struct WatchEntry: Identifiable, Codable, Equatable {
    let id: String
    let date: String
    let lucky: String
    let createdAt: Double?
}

struct WatchLocalSnapshot: Codable {
    var entries: [WatchEntry]
    var streak: Int
    var totalEntries: Int
    var totalClovers: Int
    var leafCount: Int
    var palette: String
    var lang: String
    var dark: Bool
    var name: String
    var updatedAt: Double
}

@MainActor
final class WatchSessionStore: NSObject, ObservableObject {
    static let shared = WatchSessionStore()

    @Published private(set) var entries: [WatchEntry] = []
    @Published private(set) var streak: Int = 0
    @Published private(set) var totalEntries: Int = 0
    @Published private(set) var totalClovers: Int = 0
    @Published private(set) var leafCount: Int = 0
    @Published private(set) var palette: String = "clover"
    @Published private(set) var lang: String = "zh"
    @Published private(set) var isSyncing: Bool = false

    private let cacheKey = "clovery_watch_snapshot_v1"
    private let maxCachedEntries = 30

    private override init() {
        super.init()
        loadCachedSnapshot()
        activateSession()
    }

    func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }
    }

    func requestSync() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }
        guard session.isReachable else { return }
        isSyncing = true
        session.sendMessage(["action": "requestSync"]) { [weak self] reply in
            Task { @MainActor in
                self?.isSyncing = false
                if !reply.isEmpty {
                    self?.applyContext(reply)
                }
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.isSyncing = false
            }
        }
    }

    func submitNewLucky(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let ms = now.timeIntervalSince1970 * 1000.0
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        let today = fmt.string(from: now)
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        let entryID = "watch-\(Int(ms))-\(suffix)"

        let newEntry = WatchEntry(id: entryID, date: today, lucky: trimmed, createdAt: ms)
        var updated = [newEntry] + entries.filter { $0.id != entryID }
        if updated.count > maxCachedEntries {
            updated = Array(updated.prefix(maxCachedEntries))
        }
        let hadTodayBefore = entries.contains { $0.date == today }
        entries = updated
        totalEntries += 1
        if !hadTodayBefore {
            if streak == 0 { streak = 1 }
            leafCount += 1
            if leafCount >= 4 {
                totalClovers += leafCount / 4
                leafCount = leafCount % 4
            }
        }
        saveCachedSnapshot()

        let payloadEntry: [String: Any] = [
            "id": entryID,
            "date": today,
            "lucky": trimmed,
            "mood": "lucky",
            "tags": [String](),
            "createdAt": ms,
            "updatedAt": ms,
        ]
        let message: [String: Any] = [
            "action": "createEntry",
            "entry": payloadEntry,
        ]

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let rawEntries = context["entries"] as? [[String: Any]] else { return }
        let parsed: [WatchEntry] = rawEntries.compactMap { item in
            guard let id = item["id"] as? String,
                  let date = item["date"] as? String,
                  let lucky = item["lucky"] as? String else { return nil }
            return WatchEntry(
                id: id,
                date: date,
                lucky: lucky,
                createdAt: item["createdAt"] as? Double
            )
        }

        entries = parsed
        if let s = context["streak"] as? Int { streak = s }
        if let t = context["totalEntries"] as? Int { totalEntries = t }
        if let c = context["totalClovers"] as? Int { totalClovers = c }
        if let l = context["leafCount"] as? Int { leafCount = l }
        if let p = context["palette"] as? String { palette = p }
        if let lg = context["lang"] as? String { lang = lg }
        saveCachedSnapshot()
    }

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let snap = try? JSONDecoder().decode(WatchLocalSnapshot.self, from: data) else { return }
        entries = snap.entries
        streak = snap.streak
        totalEntries = snap.totalEntries
        totalClovers = snap.totalClovers
        leafCount = snap.leafCount
        palette = snap.palette
        lang = snap.lang
    }

    private func saveCachedSnapshot() {
        let snap = WatchLocalSnapshot(
            entries: entries,
            streak: streak,
            totalEntries: totalEntries,
            totalClovers: totalClovers,
            leafCount: leafCount,
            palette: palette,
            lang: lang,
            dark: true,
            name: "",
            updatedAt: Date().timeIntervalSince1970 * 1000.0
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            let ctx = session.receivedApplicationContext
            Task { @MainActor in
                self.applyContext(ctx)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }
}
