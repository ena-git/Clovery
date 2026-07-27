import Foundation

struct BootstrapCheckpoint: Codable, Equatable {
    let accountID: String
    let vaultID: String
    let sourceKind: BootstrapSourceKind
    let updatedAt: Date
}

protocol BootstrapCheckpointStoring: AnyObject {
    func load() throws -> BootstrapCheckpoint?
    func save(_ checkpoint: BootstrapCheckpoint) throws
    func clear()
}

final class BootstrapCheckpointStore: BootstrapCheckpointStoring {
    static let storageKey = "clovery_account_bootstrap_checkpoint_v1"

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> BootstrapCheckpoint? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try decoder.decode(BootstrapCheckpoint.self, from: data)
    }

    func save(_ checkpoint: BootstrapCheckpoint) throws {
        userDefaults.set(try encoder.encode(checkpoint), forKey: Self.storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
