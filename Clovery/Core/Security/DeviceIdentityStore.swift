import Foundation
import UIKit

final class DeviceIdentityStore {
    static let account = "device-id"

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    func deviceID() throws -> String {
        if let value = try keychain.read(account: Self.account) {
            return value
        }
        let value = UUID().uuidString.lowercased()
        try keychain.save(value, account: Self.account)
        return value
    }

    func deviceRegistration() throws -> DeviceRegistration {
        DeviceRegistration(
            deviceID: try deviceID(),
            platform: "ios",
            displayName: UIDevice.current.name
        )
    }
}
