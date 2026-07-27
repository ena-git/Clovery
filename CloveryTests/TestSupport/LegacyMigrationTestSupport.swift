import Foundation
import XCTest
@testable import Clovery

struct MigrationCoordinatorFixture {
    let coordinator: LegacyMigrationCoordinator
    let preparer: MigrationArchivePreparerSpy
    let api: LegacyMigrationAPISpy
    let checkpoint: LegacyMigrationCheckpointStore
    let uploadingReport: LegacyMigrationReport
    let verifiedReport: LegacyMigrationReport
}

@MainActor
final class MigrationArchivePreparerSpy: LegacyMigrationArchivePreparing {
    let exporter: MigrationBundleExporter
    let entriesJSON: String
    private(set) var prepareCalls = 0

    init(exporter: MigrationBundleExporter, entriesJSON: String) {
        self.exporter = exporter
        self.entriesJSON = entriesJSON
    }

    func prepare(migrationID: UUID) async throws -> MigrationBundleExportResult {
        prepareCalls += 1
        return try exporter.export(migrationID: migrationID, entriesJSON: entriesJSON)
    }
}

@MainActor
final class LegacyMigrationAPISpy: LegacyMigrationAPIProtocol {
    var failEntryIDOnce: String?
    var assetState: LegacyAssetUploadState = .uploadRequired
    var reportResults: [Result<LegacyMigrationReport, Error>] = []
    var verifyError: Error?
    var verifyReport: LegacyMigrationReport
    private(set) var createRequests: [LegacyMigrationCreateRequest] = []
    private(set) var entryCalls: [String] = []
    private(set) var uploadCalls: [Data] = []
    private(set) var completeAssetCalls: [UUID] = []

    init(verifyReport: LegacyMigrationReport) {
        self.verifyReport = verifyReport
    }

    func create(_ request: LegacyMigrationCreateRequest) async throws -> LegacyMigrationRemote {
        createRequests.append(request)
        return LegacyMigrationRemote(
            migrationID: request.migrationID,
            status: .uploading
        )
    }

    func addEntry(migrationID: UUID, entry: LegacyMigrationEntryUpload) async throws {
        entryCalls.append(entry.entryID)
        if failEntryIDOnce == entry.entryID {
            failEntryIDOnce = nil
            throw URLError(.networkConnectionLost)
        }
    }

    func addAsset(
        migrationID: UUID,
        asset: LegacyMigrationAssetUpload
    ) async throws -> LegacyAssetUploadTicket {
        LegacyAssetUploadTicket(
            assetID: asset.assetID,
            status: assetState,
            uploadURL: assetState == .uploadRequired
                ? URL(string: "https://upload.example")
                : nil,
            requiredHeaders: [:],
            expiresAt: nil
        )
    }

    func uploadAsset(_ data: Data, using ticket: LegacyAssetUploadTicket) async throws {
        uploadCalls.append(data)
    }

    func completeAsset(assetID: UUID) async throws {
        completeAssetCalls.append(assetID)
    }

    func verify(migrationID: UUID) async throws -> LegacyMigrationReport {
        if let verifyError { throw verifyError }
        return verifyReport
    }

    func report(migrationID: UUID) async throws -> LegacyMigrationReport {
        guard !reportResults.isEmpty else {
            throw APIError.server(
                code: "migration_not_found",
                message: "missing",
                statusCode: 404
            )
        }
        return try reportResults.removeFirst().get()
    }

    func resetUploadCalls() {
        entryCalls = []
        uploadCalls = []
        completeAssetCalls = []
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
