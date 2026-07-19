import XCTest
@testable import Clovery

final class DeviceIdentityStoreTests: XCTestCase {
    func testDeviceIDIsStableAcrossReads() throws {
        let keychain = KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
        let store = DeviceIdentityStore(keychain: keychain)
        defer { try? keychain.delete(account: DeviceIdentityStore.account) }

        let first = try store.deviceID()
        let second = try store.deviceID()

        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first))
    }
}
