import XCTest
@testable import Clovery

final class KeychainStoreTests: XCTestCase {
    private var service: String!
    private var store: KeychainStore!

    override func setUp() {
        service = "com.clovery.tests.\(UUID().uuidString)"
        store = KeychainStore(service: service)
    }

    override func tearDown() {
        try? store.delete(account: "value")
        store = nil
        service = nil
        super.tearDown()
    }

    func testSaveReadReplaceAndDelete() throws {
        try store.save("first", account: "value")
        XCTAssertEqual(try store.read(account: "value"), "first")

        try store.save("second", account: "value")
        XCTAssertEqual(try store.read(account: "value"), "second")

        try store.delete(account: "value")
        XCTAssertNil(try store.read(account: "value"))
    }
}
