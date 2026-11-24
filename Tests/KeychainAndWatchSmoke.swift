import Foundation

// Standalone smoke unit tests runnable via swiftc on macOS / host without simulator.
// Tests KeychainTrialStore and WatchDiarySnapshot pure Swift behavior.
@main
struct CloveryBridgeSmokeRunner {
    private final class MockBacking: KeychainTrialBacking {
        var storage: [String: Data] = [:]

        func readData(service: String, account: String) -> Data? {
            storage["\(service)|\(account)"]
        }

        func writeData(_ data: Data, service: String, account: String) -> Bool {
            storage["\(service)|\(account)"] = data
            return true
        }

        func setCount(_ count: Int, service: String = "com.clovery.app.board", account: String = "board_trial_count") {
            storage["\(service)|\(account)"] = String(count).data(using: .utf8)
        }
    }

    static func main() {
        let suite = "CloverySmoke-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let backing = MockBacking()
        let store = KeychainTrialStore(backing: backing, fallbackDefaults: defaults)

        assert(store.sync(localCount: 0) == 0, "empty sync should return 0")
        assert(store.increment(localCount: 0) == 1, "first increment should be 1")
        assert(store.sync(localCount: 0) == 1, "keychain count should override lower local count")

        backing.setCount(3)
        let freshStore = KeychainTrialStore(backing: backing, fallbackDefaults: defaults)
        assert(freshStore.sync(localCount: 0) == 3, "keychain count should survive reinstall")
        assert(freshStore.increment(localCount: 3) == 3, "increment must cap at maxTrials (3)")

        let json = """
        [
          {"id":"irene-welcome","date":"2000-01-01","lucky":"Hi","isWelcome":true},
          {"id":"e1","date":"2026-11-24","lucky":"Hot tea","createdAt":1760000000000},
          {"id":"e2","date":"2026-11-23","lucky":"Sunny day","createdAt":1759900000000},
          {"id":"e3","date":"2026-11-22","lucky":"Good book","createdAt":1759800000000},
          {"id":"e4","date":"2026-11-21","lucky":"Warm scarf","createdAt":1759700000000},
          {"id":"e5","date":"2026-11-20","lucky":"Early train","createdAt":1759600000000}
        ]
        """
        let snap = WatchDiarySnapshot.build(
            from: json,
            name: "Tester",
            palette: "clover",
            lang: "zh",
            dark: false
        )
        assert(snap.totalEntries == 5, "welcome entry must be excluded from watch total")
        assert(snap.totalClovers == 1 && snap.leafCount == 1, "5 unique days -> 1 clover + 1 leaf")
        assert(snap.entries.count == 5, "all 5 real entries included")
        assert(snap.entries.first?.id == "e1", "entries sorted newest first")

        print("CloveryBridgeSmokeRunner PASSED")
    }
}
