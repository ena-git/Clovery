import CryptoKit
import Foundation

enum LegacyMigrationOutcome: Equatable {
    case verified(LegacyMigrationReport)
    case needsAttention(String)
}

@MainActor
final class LegacyMigrationCoordinator {
    private let archivePreparer: LegacyMigrationArchivePreparing
    private let archiveReader: LegacyMigrationArchiveReader
    private let api: LegacyMigrationAPIProtocol
    private let checkpointStore: LegacyMigrationCheckpointStoring
    private let migrationIDGenerator: () -> UUID

    init(
        archivePreparer: LegacyMigrationArchivePreparing,
        archiveReader: LegacyMigrationArchiveReader = LegacyMigrationArchiveReader(),
        api: LegacyMigrationAPIProtocol,
        checkpointStore: LegacyMigrationCheckpointStoring,
        migrationIDGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.archivePreparer = archivePreparer
        self.archiveReader = archiveReader
        self.api = api
        self.checkpointStore = checkpointStore
        self.migrationIDGenerator = migrationIDGenerator
    }

    func run(
        accountID: String,
        vaultID: String
    ) async throws -> LegacyMigrationOutcome {
        do {
            return try await performRun(accountID: accountID, vaultID: vaultID)
        } catch let error as APIError where Self.needsAttention(error) {
            return .needsAttention(error.code ?? "migration_needs_attention")
        }
    }

    private func performRun(
        accountID: String,
        vaultID: String
    ) async throws -> LegacyMigrationOutcome {
        let stored = try checkpointStore.load(accountID: accountID, vaultID: vaultID)
        var checkpoint: LegacyMigrationCheckpoint
        if let stored {
            checkpoint = stored
        } else {
            checkpoint = try await makeCheckpoint(
                accountID: accountID,
                vaultID: vaultID
            )
        }
        let archive = try archiveReader.read(
            from: URL(fileURLWithPath: checkpoint.archivePath)
        )

        var remoteExists = false
        if stored != nil {
            do {
                let report = try await api.report(migrationID: checkpoint.migrationID)
                remoteExists = true
                if report.status == .verified {
                    return try finalize(
                        report: report,
                        archive: archive,
                        checkpoint: &checkpoint
                    )
                }
                if report.status == .needsAttention {
                    return .needsAttention("migration_needs_attention")
                }
            } catch let error as APIError
                where error.code == "migration_not_found" || error.statusCode == 404 {
                remoteExists = false
            }
        }

        if !remoteExists {
            let created = try await api.create(
                archive.createRequest(migrationID: checkpoint.migrationID)
            )
            guard created.migrationID == checkpoint.migrationID else {
                return .needsAttention("migration_id_mismatch")
            }
        }

        for entry in archive.entries
            where !checkpoint.uploadedEntryIDs.contains(entry.entryID) {
            try await api.addEntry(migrationID: checkpoint.migrationID, entry: entry)
            checkpoint.uploadedEntryIDs.insert(entry.entryID)
            try checkpointStore.save(checkpoint)
        }

        for asset in archive.assets
            where !checkpoint.uploadedPhotoNames.contains(asset.filename) {
            let assetID = Self.assetID(
                migrationID: checkpoint.migrationID,
                filename: asset.filename
            )
            let ticket = try await api.addAsset(
                migrationID: checkpoint.migrationID,
                asset: LegacyMigrationAssetUpload(
                    assetID: assetID,
                    sourceFilename: asset.filename,
                    contentType: "image/jpeg",
                    byteSize: asset.bytes,
                    sha256: asset.sha256
                )
            )
            switch ticket.status {
            case .uploadRequired:
                try await api.uploadAsset(asset.data, using: ticket)
                try await api.completeAsset(assetID: ticket.assetID)
            case .complete:
                break
            }
            checkpoint.uploadedPhotoNames.insert(asset.filename)
            try checkpointStore.save(checkpoint)
        }

        let report = try await api.verify(migrationID: checkpoint.migrationID)
        return try finalize(
            report: report,
            archive: archive,
            checkpoint: &checkpoint
        )
    }

    private func makeCheckpoint(
        accountID: String,
        vaultID: String
    ) async throws -> LegacyMigrationCheckpoint {
        let migrationID = migrationIDGenerator()
        let result = try await archivePreparer.prepare(migrationID: migrationID)
        let checkpoint = LegacyMigrationCheckpoint(
            accountID: accountID,
            vaultID: vaultID,
            migrationID: migrationID,
            archivePath: result.archiveURL.path,
            uploadedEntryIDs: [],
            uploadedPhotoNames: [],
            verifiedAt: nil
        )
        try checkpointStore.save(checkpoint)
        return checkpoint
    }

    private func finalize(
        report: LegacyMigrationReport,
        archive: LegacyMigrationArchive,
        checkpoint: inout LegacyMigrationCheckpoint
    ) throws -> LegacyMigrationOutcome {
        guard report.status == .verified,
              report.migrationID == checkpoint.migrationID,
              report.expectedEntries == archive.manifest.entryCount,
              report.importedEntries == archive.manifest.entryCount,
              report.expectedDeletedEntries == archive.manifest.deletedCount,
              report.importedDeletedEntries == archive.manifest.deletedCount,
              report.expectedAssets == archive.assets.count,
              report.verifiedAssets == archive.assets.count,
              report.expectedBytes == archive.totalBytes,
              report.verifiedBytes == archive.totalBytes,
              let verifiedAt = report.verifiedAt else {
            return .needsAttention("migration_report_mismatch")
        }
        checkpoint.verifiedAt = verifiedAt
        try checkpointStore.save(checkpoint)
        return .verified(report)
    }

    private static func needsAttention(_ error: APIError) -> Bool {
        switch error.code {
        case "migration_verification_failed", "migration_conflict",
             "invalid_migration_bundle", "asset_id_reused",
             "asset_integrity_mismatch":
            true
        default:
            false
        }
    }

    private static func assetID(migrationID: UUID, filename: String) -> UUID {
        let input = Data("\(migrationID.uuidString.lowercased()):\(filename)".utf8)
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
