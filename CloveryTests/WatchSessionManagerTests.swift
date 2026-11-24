import XCTest
@testable import Clovery

@MainActor
final class WatchSessionManagerTests: XCTestCase {
    func testBuildSnapshotFiltersWelcomeComputesCloversAndCapsAt30Entries() {
        var entries: [[String: Any]] = [
            [
                "id": "irene-welcome",
                "date": "2000-01-01",
                "lucky": "Welcome",
                "isWelcome": true,
            ]
        ]
        for idx in 1...35 {
            let day = String(format: "%02d", ((idx - 1) % 28) + 1)
            entries.append([
                "id": "entry-\(idx)",
                "date": "2026-05-\(day)",
                "lucky": "Lucky \(idx)",
                "createdAt": Double(1_700_000_000_000 + idx),
            ])
        }
        let data = try! JSONSerialization.data(withJSONObject: entries)
        let json = String(data: data, encoding: .utf8)!

        let snapshot = WatchDiarySnapshot.build(
            from: json,
            name: "Hua",
            palette: "sakura",
            lang: "zh",
            dark: true
        )

        XCTAssertEqual(snapshot.entries.count, 30)
        XCTAssertFalse(snapshot.entries.contains(where: { $0.id == "irene-welcome" }))
        XCTAssertEqual(snapshot.totalEntries, 35)
        XCTAssertEqual(snapshot.totalClovers, 7)
        XCTAssertEqual(snapshot.leafCount, 0)
        XCTAssertEqual(snapshot.palette, "sakura")
        XCTAssertEqual(snapshot.lang, "zh")
    }

    func testPendingQueueDeduplicatesAndClearsByID() {
        let manager = WatchSessionManager(isAvailable: { false })
        manager.clearPendingEntries(ids: manager.pendingEntries().compactMap { $0["id"] as? String })

        let watchEntry: [String: Any] = [
            "id": "watch-test-1",
            "date": "2026-11-24",
            "lucky": "Caught a warm breeze",
            "createdAt": 1_760_000_000_000.0,
        ]
        manager.enqueueIncomingWatchEntry(watchEntry)
        manager.enqueueIncomingWatchEntry(watchEntry)

        XCTAssertEqual(manager.pendingEntries().count, 1)

        manager.clearPendingEntries(ids: ["watch-test-1"])
        XCTAssertTrue(manager.pendingEntries().isEmpty)
    }
}
