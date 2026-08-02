import CryptoKit
import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacyMigrationCoordinatorTests: XCTestCase {
    func testInterruptedEntryUploadResumesCheckpointWithoutReExporting() async throws {
        let fixture = try makeFixture(
            entriesJSON: #"[{"id":"entry-1","text":"one"},{"id":"entry-2","text":"two"}]"#
        )
        fixture.api.failEntryIDOnce = "entry-2"

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.coordinator.run(accountID: "account", vaultID: "vault")
        }
        let interrupted = try XCTUnwrap(
            fixture.checkpoint.load(accountID: "account", vaultID: "vault")
        )
        XCTAssertEqual(interrupted.uploadedEntryIDs, ["entry-1"])

        fixture.api.reportResults = [.success(fixture.uploadingReport)]
        let outcome = try await fixture.coordinator.run(
            accountID: "account",
            vaultID: "vault"
        )

        XCTAssertEqual(outcome, .verified(fixture.verifiedReport))
        XCTAssertEqual(fixture.preparer.prepareCalls, 1)
        XCTAssertEqual(fixture.api.entryCalls.filter { $0 == "entry-1" }.count, 1)
        XCTAssertEqual(fixture.api.entryCalls.filter { $0 == "entry-2" }.count, 2)
    }

    func testRequiredAssetUploadsThenCompletesAndCompleteAssetSkipsBinaryUpload() async throws {
        let required = try makeFixture(
            entriesJSON: #"[{"id":"entry-1","photos":["photo-1.jpg"]}]"#,
            photoData: Data([1, 2, 3])
        )
        required.api.assetState = .uploadRequired

        _ = try await required.coordinator.run(accountID: "account", vaultID: "vault")

        XCTAssertEqual(required.api.uploadCalls, [Data([1, 2, 3])])
        XCTAssertEqual(required.api.completeAssetCalls.count, 1)
        XCTAssertEqual(
            try required.checkpoint.load(accountID: "account", vaultID: "vault")?
                .uploadedPhotoNames,
            ["photo-1.jpg"]
        )

        let complete = try makeFixture(
            entriesJSON: #"[{"id":"entry-1","photos":["photo-1.jpg"]}]"#,
            photoData: Data([1, 2, 3])
        )
        complete.api.assetState = .complete

        _ = try await complete.coordinator.run(accountID: "account", vaultID: "vault")

        XCTAssertTrue(complete.api.uploadCalls.isEmpty)
        XCTAssertTrue(complete.api.completeAssetCalls.isEmpty)
    }

    func testVerifiedReportOnRestartSkipsUploadAndMarksCheckpoint() async throws {
        let fixture = try makeFixture(entriesJSON: #"[{"id":"entry-1"}]"#)
        _ = try await fixture.coordinator.run(accountID: "account", vaultID: "vault")
        fixture.api.resetUploadCalls()
        fixture.api.reportResults = [.success(fixture.verifiedReport)]

        let outcome = try await fixture.coordinator.run(accountID: "account", vaultID: "vault")

        XCTAssertEqual(outcome, .verified(fixture.verifiedReport))
        XCTAssertTrue(fixture.api.entryCalls.isEmpty)
        XCTAssertEqual(
            try fixture.checkpoint.load(accountID: "account", vaultID: "vault")?
                .verifiedAt,
            fixture.verifiedReport.verifiedAt
        )
    }

    func testVerificationFailureRetainsArchiveAndCheckpointForSupport() async throws {
        let fixture = try makeFixture(entriesJSON: #"[{"id":"entry-1"}]"#)
        fixture.api.verifyError = APIError.server(
            code: "migration_verification_failed",
            message: "failed",
            statusCode: 422
        )

        let outcome = try await fixture.coordinator.run(accountID: "account", vaultID: "vault")

        XCTAssertEqual(outcome, .needsAttention("migration_verification_failed"))
        let checkpoint = try XCTUnwrap(
            fixture.checkpoint.load(accountID: "account", vaultID: "vault")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.archivePath))
    }

    func testDifferentAccountCannotUseExistingMigrationCheckpoint() async throws {
        let fixture = try makeFixture(entriesJSON: #"[{"id":"entry-1"}]"#)
        _ = try await fixture.coordinator.run(accountID: "account", vaultID: "vault")
        fixture.api.resetUploadCalls()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.coordinator.run(accountID: "other", vaultID: "other-vault")
        }

        XCTAssertTrue(fixture.api.entryCalls.isEmpty)
        XCTAssertEqual(fixture.preparer.prepareCalls, 1)
    }

    func testCreateUsesExactArchivedManifestAndDuplicateReportStillVerifies() async throws {
        let fixture = try makeFixture(entriesJSON: #"[{"id":"entry-1"}]"#)
        fixture.api.verifyReport = LegacyMigrationReport(
            migrationID: fixture.verifiedReport.migrationID,
            status: .verified,
            expectedEntries: 1,
            importedEntries: 1,
            insertedEntries: 0,
            duplicateEntries: 1,
            conflictCopies: 0,
            expectedDeletedEntries: 0,
            importedDeletedEntries: 0,
            expectedAssets: 0,
            verifiedAssets: 0,
            expectedBytes: fixture.verifiedReport.expectedBytes,
            verifiedBytes: fixture.verifiedReport.verifiedBytes,
            verifiedAt: fixture.verifiedReport.verifiedAt
        )

        let outcome = try await fixture.coordinator.run(
            accountID: "account",
            vaultID: "vault"
        )
        let checkpoint = try XCTUnwrap(
            fixture.checkpoint.load(accountID: "account", vaultID: "vault")
        )
        let files = try MigrationBundleArchive.read(
            from: URL(fileURLWithPath: checkpoint.archivePath)
        )
        let manifestData = try XCTUnwrap(files["manifest.json"])
        let request = try XCTUnwrap(fixture.api.createRequests.first)

        XCTAssertEqual(outcome, .verified(fixture.api.verifyReport))
        XCTAssertEqual(request.manifestBase64, manifestData.base64EncodedString())
        XCTAssertEqual(
            request.manifestSHA256,
            SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func makeFixture(
        entriesJSON: String,
        photoData: Data? = nil
    ) throws -> MigrationCoordinatorFixture {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: documents.appendingPathComponent("photos", isDirectory: true),
            withIntermediateDirectories: true
        )
        if let photoData {
            try photoData.write(
                to: documents.appendingPathComponent("photos/photo-1.jpg")
            )
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: documents)
        }

        let migrationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let preparer = MigrationArchivePreparerSpy(
            exporter: MigrationBundleExporter(documentsDirectory: documents),
            entriesJSON: entriesJSON
        )
        let checkpoint = LegacyMigrationCheckpointStore(documentsDirectory: documents)
        let expected = try expectedReport(
            migrationID: migrationID,
            entriesJSON: entriesJSON,
            photoData: photoData
        )
        let api = LegacyMigrationAPISpy(verifyReport: expected.verified)
        let coordinator = LegacyMigrationCoordinator(
            archivePreparer: preparer,
            archiveReader: LegacyMigrationArchiveReader(),
            api: api,
            checkpointStore: checkpoint,
            migrationIDGenerator: { migrationID }
        )
        return MigrationCoordinatorFixture(
            coordinator: coordinator,
            preparer: preparer,
            api: api,
            checkpoint: checkpoint,
            uploadingReport: expected.uploading,
            verifiedReport: expected.verified
        )
    }

    private func expectedReport(
        migrationID: UUID,
        entriesJSON: String,
        photoData: Data?
    ) throws -> (uploading: LegacyMigrationReport, verified: LegacyMigrationReport) {
        let entries = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(entriesJSON.utf8)) as? [[String: Any]]
        )
        let entryBytes = try entries.reduce(into: 0) { total, entry in
            total += try JSONSerialization.data(
                withJSONObject: entry,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ).count
        }
        let bytes = Int64(entryBytes + (photoData?.count ?? 0))
        let base = LegacyMigrationReport(
            migrationID: migrationID,
            status: .uploading,
            expectedEntries: entries.count,
            importedEntries: 0,
            insertedEntries: 0,
            duplicateEntries: 0,
            conflictCopies: 0,
            expectedDeletedEntries: 0,
            importedDeletedEntries: 0,
            expectedAssets: photoData == nil ? 0 : 1,
            verifiedAssets: 0,
            expectedBytes: bytes,
            verifiedBytes: 0,
            verifiedAt: nil
        )
        return (
            base,
            LegacyMigrationReport(
                migrationID: migrationID,
                status: .verified,
                expectedEntries: base.expectedEntries,
                importedEntries: base.expectedEntries,
                insertedEntries: base.expectedEntries,
                duplicateEntries: 0,
                conflictCopies: 0,
                expectedDeletedEntries: 0,
                importedDeletedEntries: 0,
                expectedAssets: base.expectedAssets,
                verifiedAssets: base.expectedAssets,
                expectedBytes: bytes,
                verifiedBytes: bytes,
                verifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }
}
