import Foundation
import XCTest
@testable import Clovery

final class LegacyMigrationCheckpointStoreTests: XCTestCase {
    func testAtomicSaveAndCrashRecoveryPreserveProgress() throws {
        let directory = try temporaryDirectory()
        let store = LegacyMigrationCheckpointStore(documentsDirectory: directory)
        var checkpoint = Self.checkpoint
        checkpoint.uploadedEntryIDs = ["entry-1", "entry-2"]
        checkpoint.uploadedPhotoNames = ["photo-1.jpg"]

        try store.save(checkpoint)
        let recovered = try LegacyMigrationCheckpointStore(
            documentsDirectory: directory
        ).load(accountID: "account", vaultID: "vault")

        XCTAssertEqual(recovered, checkpoint)
        let migrationDirectory = directory.appendingPathComponent("CloveryMigration")
        let filenames = try FileManager.default.contentsOfDirectory(atPath: migrationDirectory.path)
        XCTAssertEqual(filenames, ["checkpoint.json"])
    }

    func testSameAccountReusesCheckpointAndDifferentAccountIsRejected() throws {
        let directory = try temporaryDirectory()
        let store = LegacyMigrationCheckpointStore(documentsDirectory: directory)
        try store.save(Self.checkpoint)

        XCTAssertEqual(
            try store.load(accountID: "account", vaultID: "vault"),
            Self.checkpoint
        )
        XCTAssertThrowsError(
            try store.load(accountID: "other", vaultID: "other-vault")
        ) { error in
            guard case LegacyMigrationCheckpointError.accountMismatch = error else {
                return XCTFail("Expected accountMismatch, got \(error)")
            }
        }
    }

    func testArchivePathIsStoredRelativeToDocumentsAndResolvedOnLoad() throws {
        let directory = try temporaryDirectory()
        let store = LegacyMigrationCheckpointStore(documentsDirectory: directory)
        let archiveURL = directory
            .appendingPathComponent("CloveryMigration/archive/migration_bundle.zip")
        let checkpoint = Self.checkpoint(archivePath: archiveURL.path)

        try store.save(checkpoint)

        let checkpointData = try Data(
            contentsOf: directory.appendingPathComponent("CloveryMigration/checkpoint.json")
        )
        let checkpointText = String(decoding: checkpointData, as: UTF8.self)
        XCTAssertFalse(checkpointText.contains(directory.path))
        XCTAssertEqual(
            try store.load(accountID: "account", vaultID: "vault")?.archivePath,
            archiveURL.path
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-checkpoint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private static let checkpoint = checkpoint(
        archivePath: "/documents/CloveryMigration/archive/migration_bundle.zip"
    )

    private static func checkpoint(archivePath: String) -> LegacyMigrationCheckpoint {
        LegacyMigrationCheckpoint(
            accountID: "account",
            vaultID: "vault",
            migrationID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            archivePath: archivePath,
            uploadedEntryIDs: [],
            uploadedPhotoNames: [],
            verifiedAt: nil
        )
    }
}
