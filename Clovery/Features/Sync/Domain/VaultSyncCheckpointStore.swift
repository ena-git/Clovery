import CryptoKit
import Foundation

struct VaultSyncNamespace: Codable, Equatable, Hashable {
    let accountID: String
    let vaultID: String

    var storageKey: String {
        let identity = "\(accountID)\u{0}\(vaultID)"
        return SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct VaultEntryMirror: Codable, Equatable {
    let revision: Int
    let payloadHash: String
    let payload: JSONValue
}

enum VaultAssetCheckpointStatus: String, Codable, Equatable {
    case pending
    case complete
}

struct VaultAssetCheckpoint: Codable, Equatable {
    let assetID: UUID
    let sha256: String
    let byteSize: Int64
    let status: VaultAssetCheckpointStatus
}

struct VaultSyncState: Codable, Equatable {
    var cursor: Int64
    var entries: [String: VaultEntryMirror]
    var pendingOperations: [VaultSyncOperation]
    var assets: [String: VaultAssetCheckpoint]
    var appliedOperationIDs: Set<UUID>
    var restoredMigrationID: UUID?

    static let empty = VaultSyncState(
        cursor: 0,
        entries: [:],
        pendingOperations: [],
        assets: [:],
        appliedOperationIDs: [],
        restoredMigrationID: nil
    )
}

protocol VaultSyncCheckpointStoring: AnyObject {
    func load(for namespace: VaultSyncNamespace) throws -> VaultSyncState
    func save(_ state: VaultSyncState, for namespace: VaultSyncNamespace) throws
}

final class VaultSyncCheckpointStore: VaultSyncCheckpointStoring {
    private let baseDirectory: URL
    private let fileStore: AtomicJSONFileStore

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.baseDirectory = applicationSupport
                .appendingPathComponent("Clovery/VaultSync", isDirectory: true)
        }
        self.fileStore = AtomicJSONFileStore(fileManager: fileManager)
    }

    func load(for namespace: VaultSyncNamespace) throws -> VaultSyncState {
        try fileStore.read(VaultSyncState.self, from: fileURL(for: namespace)) ?? .empty
    }

    func save(_ state: VaultSyncState, for namespace: VaultSyncNamespace) throws {
        try fileStore.write(
            state,
            to: fileURL(for: namespace),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func fileURL(for namespace: VaultSyncNamespace) -> URL {
        baseDirectory.appendingPathComponent("\(namespace.storageKey).json")
    }
}

enum VaultPayloadHash {
    static func make(_ payload: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
