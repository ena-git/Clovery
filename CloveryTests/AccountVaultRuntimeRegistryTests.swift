import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountVaultRuntimeRegistryTests: XCTestCase {
    func testDifferentAccountsUseDifferentLocalBackupAndPhotoNamespaces() throws {
        let directory = temporaryDirectory()
        let registry = AccountVaultRuntimeRegistry(
            documentsDirectory: directory,
            syncAPI: RegistrySyncAPISpy(),
            assetAPI: RegistryAssetAPISpy(),
            checkpointStore: VaultSyncCheckpointStore(
                baseDirectory: directory.appendingPathComponent("checkpoints")
            )
        )
        let firstNamespace = VaultSyncNamespace(accountID: "account-a", vaultID: "vault-a")
        let secondNamespace = VaultSyncNamespace(accountID: "account-b", vaultID: "vault-b")
        let first = registry.context(for: firstNamespace)
        try first.localStore.save(VaultDiarySnapshot(
            entries: [["id": .string("first"), "text": .string("private")]],
            deletedIDs: [],
            name: nil
        ))

        let second = registry.context(for: secondNamespace)

        XCTAssertNotEqual(first.accountDirectory, second.accountDirectory)
        XCTAssertEqual(try second.localStore.load(), .empty)
        XCTAssertTrue(first.accountDirectory.path.contains(firstNamespace.storageKey))
        XCTAssertTrue(second.accountDirectory.path.contains(secondNamespace.storageKey))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

@MainActor
private final class RegistrySyncAPISpy: VaultSyncAPIProtocol {
    func push(_ operations: [VaultSyncOperation]) async throws -> [VaultSyncDecision] { [] }
    func pull(cursor: Int64, limit: Int) async throws -> VaultSyncPage {
        VaultSyncPage(changes: [], nextCursor: cursor, hasMore: false)
    }
}

@MainActor
private final class RegistryAssetAPISpy: VaultAssetAPIProtocol {
    func listMigrationAssets(migrationID: UUID) async throws -> [VaultMigrationAsset] { [] }
    func startUpload(_ request: VaultAssetUploadRequest) async throws -> VaultAssetUploadTicket {
        VaultAssetUploadTicket(
            assetID: request.assetID,
            status: .complete,
            uploadURL: nil,
            requiredHeaders: [:],
            expiresAt: nil
        )
    }
    func upload(_ data: Data, using ticket: VaultAssetUploadTicket) async throws {}
    func complete(assetID: UUID) async throws {}
    func downloadTicket(assetID: UUID) async throws -> VaultAssetDownloadTicket {
        VaultAssetDownloadTicket(
            assetID: assetID,
            downloadURL: URL(string: "https://objects.example")!,
            expiresAt: "2026-07-27T00:00:00Z"
        )
    }
    func download(using ticket: VaultAssetDownloadTicket) async throws -> Data { Data() }
}
