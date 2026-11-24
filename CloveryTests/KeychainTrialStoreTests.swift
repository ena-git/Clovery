import XCTest
@testable import Clovery

final class KeychainTrialStoreTests: XCTestCase {
    private final class InMemoryBacking: KeychainTrialBacking {
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

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KeychainTrialStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSyncTakesMaxAndWritesToKeychainWhenEmpty() {
        let backing = InMemoryBacking()
        let store = KeychainTrialStore(backing: backing, fallbackDefaults: defaults)

        let synced = store.sync(localCount: 2)

        XCTAssertEqual(synced, 2)
        XCTAssertEqual(store.currentCount(), 2)
    }

    func testSyncPreservesHigherKeychainCountAcrossReinstall() {
        let backing = InMemoryBacking()
        backing.setCount(3)
        let store = KeychainTrialStore(backing: backing, fallbackDefaults: defaults)

        let synced = store.sync(localCount: 0)

        XCTAssertEqual(synced, 3)
        XCTAssertEqual(store.currentCount(), 3)
    }

    func testIncrementCapsAtMaxTrials() {
        let backing = InMemoryBacking()
        backing.setCount(2)
        let store = KeychainTrialStore(backing: backing, fallbackDefaults: defaults)

        let first = store.increment(localCount: 2)
        let second = store.increment(localCount: 3)

        XCTAssertEqual(first, 3)
        XCTAssertEqual(second, KeychainTrialStore.maxTrials)
        XCTAssertEqual(store.currentCount(), 3)
    }
}
