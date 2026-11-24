import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct WatchDiarySnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: String
        let date: String
        let lucky: String
        let createdAt: Double?
    }

    let entries: [Entry]
    let streak: Int
    let totalEntries: Int
    let totalClovers: Int
    let leafCount: Int
    let palette: String
    let lang: String
    let dark: Bool
    let name: String
    let updatedAt: Double

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    static func build(
        from rawEntriesJSON: String,
        name: String,
        palette: String,
        lang: String,
        dark: Bool,
        referenceDate: Date = Date()
    ) -> WatchDiarySnapshot {
        let parsed: [[String: Any]]
        if let data = rawEntriesJSON.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            parsed = arr
        } else {
            parsed = []
        }

        let realEntries = parsed.filter { ($0["isWelcome"] as? Bool) != true }
        let snapshotEntries: [Entry] = realEntries
            .sorted {
                let d1 = ($0["date"] as? String) ?? ""
                let d2 = ($1["date"] as? String) ?? ""
                if d1 != d2 { return d1 > d2 }
                let c1 = ($0["createdAt"] as? Double) ?? 0
                let c2 = ($1["createdAt"] as? Double) ?? 0
                return c1 > c2
            }
            .prefix(30)
            .compactMap { dict in
                guard let id = dict["id"] as? String,
                      let date = dict["date"] as? String,
                      let lucky = dict["lucky"] as? String else { return nil }
                return Entry(
                    id: id,
                    date: date,
                    lucky: lucky,
                    createdAt: dict["createdAt"] as? Double
                )
            }

        let uniqueDays = Set(realEntries.compactMap { $0["date"] as? String }.filter { !$0.isEmpty })
        let streak = computeStreak(days: uniqueDays, referenceDate: referenceDate)
        let dayCount = uniqueDays.count

        return WatchDiarySnapshot(
            entries: snapshotEntries,
            streak: streak,
            totalEntries: realEntries.count,
            totalClovers: dayCount / 4,
            leafCount: dayCount % 4,
            palette: palette,
            lang: lang,
            dark: dark,
            name: name,
            updatedAt: referenceDate.timeIntervalSince1970 * 1000.0
        )
    }

    private static func computeStreak(days: Set<String>, referenceDate: Date) -> Int {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        let today = fmt.string(from: referenceDate)
        let startOffset = days.contains(today) ? 0 : 1
        guard let firstCheck = cal.date(byAdding: .day, value: -startOffset, to: referenceDate),
              days.contains(fmt.string(from: firstCheck)) else {
            return 0
        }
        var streak = 0
        while let dayDate = cal.date(byAdding: .day, value: -(startOffset + streak), to: referenceDate),
              days.contains(fmt.string(from: dayDate)) {
            streak += 1
        }
        return streak
    }
}

/// Manages bidirectional sync between the iPhone/iPad app and the Apple Watch
/// companion app via WatchConnectivity.
@MainActor
final class WatchSessionManager: NSObject {
    static let shared = WatchSessionManager()

    private let isAvailable: () -> Bool
    private let pendingDefaultsKey = "clovery_pending_watch_entries"
    private var latestSnapshot: WatchDiarySnapshot?

    var onPendingEntriesAvailable: (([[String: Any]]) -> Void)?

    init(isAvailable: @escaping () -> Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }) {
        self.isAvailable = isAvailable
        super.init()
    }

    func activate() {
        #if canImport(WatchConnectivity)
        guard isAvailable(), WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    func updateSnapshot(
        entriesJSON: String,
        name: String,
        palette: String,
        lang: String,
        dark: Bool
    ) {
        let snapshot = WatchDiarySnapshot.build(
            from: entriesJSON,
            name: name,
            palette: palette,
            lang: lang,
            dark: dark
        )
        latestSnapshot = snapshot
        pushSnapshotToWatch(snapshot)
    }

    func pendingEntries() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: pendingDefaultsKey),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    func clearPendingEntries(ids: [String]) {
        let idSet = Set(ids)
        let remaining = pendingEntries().filter { entry in
            guard let id = entry["id"] as? String else { return false }
            return !idSet.contains(id)
        }
        savePendingEntries(remaining)
    }

    func enqueueIncomingWatchEntry(_ entry: [String: Any]) {
        guard let id = entry["id"] as? String, !id.isEmpty else { return }
        var current = pendingEntries()
        if !current.contains(where: { ($0["id"] as? String) == id }) {
            current.append(entry)
            savePendingEntries(current)
        }
        onPendingEntriesAvailable?(current)
    }

    private func savePendingEntries(_ entries: [[String: Any]]) {
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
        } else if let data = try? JSONSerialization.data(withJSONObject: entries) {
            UserDefaults.standard.set(data, forKey: pendingDefaultsKey)
        }
    }

    private func resolvedSnapshot() -> WatchDiarySnapshot? {
        if let latestSnapshot {
            return latestSnapshot
        }
        guard let shared = UserDefaults(suiteName: "group.com.clovery.app"),
              let entriesJSON = shared.string(forKey: "widget_entries"),
              !entriesJSON.isEmpty else {
            return nil
        }
        let built = WatchDiarySnapshot.build(
            from: entriesJSON,
            name: shared.string(forKey: "widget_name") ?? "",
            palette: shared.string(forKey: "widget_palette") ?? "clover",
            lang: shared.string(forKey: "widget_lang") ?? "zh",
            dark: shared.bool(forKey: "widget_dark")
        )
        latestSnapshot = built
        return built
    }

    private func pushSnapshotToWatch(_ snapshot: WatchDiarySnapshot) {
        #if canImport(WatchConnectivity)
        guard isAvailable(), WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isWatchAppInstalled else { return }
        let payload = snapshot.toDictionary()
        guard !payload.isEmpty else { return }
        try? session.updateApplicationContext(payload)
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let snapshot = self.resolvedSnapshot() {
                self.pushSnapshotToWatch(snapshot)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let action = message["action"] as? String
        if action == "requestSync" {
            Task { @MainActor in
                replyHandler(self.resolvedSnapshot()?.toDictionary() ?? [:])
            }
            return
        }
        if action == "createEntry", let entry = message["entry"] as? [String: Any] {
            Task { @MainActor in
                self.enqueueIncomingWatchEntry(entry)
                replyHandler(["status": "received"])
            }
            return
        }
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if (userInfo["action"] as? String) == "createEntry",
           let entry = userInfo["entry"] as? [String: Any] {
            Task { @MainActor in
                self.enqueueIncomingWatchEntry(entry)
            }
        }
    }
}
#endif
