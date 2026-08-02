import Foundation

struct LegacyMigrationCheckpoint: Equatable {
    let accountID: String
    let vaultID: String
    let migrationID: UUID
    let archivePath: String
    var uploadedEntryIDs: Set<String>
    var uploadedPhotoNames: Set<String>
    var verifiedAt: Date?
}

extension LegacyMigrationCheckpoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case accountID
        case vaultID
        case migrationID
        case archivePath
        case uploadedEntryIDs
        case uploadedPhotoNames
        case verifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(String.self, forKey: .accountID)
        vaultID = try container.decode(String.self, forKey: .vaultID)
        migrationID = try container.decode(UUID.self, forKey: .migrationID)
        archivePath = try container.decode(String.self, forKey: .archivePath)
        uploadedEntryIDs = Set(
            try container.decode([String].self, forKey: .uploadedEntryIDs)
        )
        uploadedPhotoNames = Set(
            try container.decode([String].self, forKey: .uploadedPhotoNames)
        )
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(vaultID, forKey: .vaultID)
        try container.encode(migrationID, forKey: .migrationID)
        try container.encode(archivePath, forKey: .archivePath)
        try container.encode(uploadedEntryIDs.sorted(), forKey: .uploadedEntryIDs)
        try container.encode(uploadedPhotoNames.sorted(), forKey: .uploadedPhotoNames)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
    }
}

enum LegacyMigrationCheckpointError: Error, Equatable {
    case accountMismatch
}

protocol LegacyMigrationCheckpointStoring: AnyObject {
    func load(accountID: String, vaultID: String) throws -> LegacyMigrationCheckpoint?
    func save(_ checkpoint: LegacyMigrationCheckpoint) throws
}

final class LegacyMigrationCheckpointStore: LegacyMigrationCheckpointStoring {
    private let fileStore: AtomicJSONFileStore
    private let documentsDirectory: URL
    private let checkpointURL: URL

    init(
        documentsDirectory: URL,
        fileStore: AtomicJSONFileStore = AtomicJSONFileStore()
    ) {
        self.fileStore = fileStore
        self.documentsDirectory = documentsDirectory.standardizedFileURL
        self.checkpointURL = documentsDirectory
            .appendingPathComponent("CloveryMigration", isDirectory: true)
            .appendingPathComponent("checkpoint.json")
    }

    func load(
        accountID: String,
        vaultID: String
    ) throws -> LegacyMigrationCheckpoint? {
        guard let stored = try fileStore.read(
            LegacyMigrationCheckpoint.self,
            from: checkpointURL
        ) else {
            return nil
        }
        let checkpoint = resolvingArchivePath(in: stored)
        guard checkpoint.accountID == accountID,
              checkpoint.vaultID == vaultID else {
            throw LegacyMigrationCheckpointError.accountMismatch
        }
        return checkpoint
    }

    func save(_ checkpoint: LegacyMigrationCheckpoint) throws {
        try fileStore.write(storingRelativeArchivePath(in: checkpoint), to: checkpointURL)
    }

    private func storingRelativeArchivePath(
        in checkpoint: LegacyMigrationCheckpoint
    ) -> LegacyMigrationCheckpoint {
        let archiveURL = URL(fileURLWithPath: checkpoint.archivePath).standardizedFileURL
        let documentsPath = documentsDirectory.path + "/"
        guard archiveURL.path.hasPrefix(documentsPath) else { return checkpoint }
        return copy(
            checkpoint,
            archivePath: String(archiveURL.path.dropFirst(documentsPath.count))
        )
    }

    private func resolvingArchivePath(
        in checkpoint: LegacyMigrationCheckpoint
    ) -> LegacyMigrationCheckpoint {
        guard !checkpoint.archivePath.hasPrefix("/") else { return checkpoint }
        return copy(
            checkpoint,
            archivePath: documentsDirectory
                .appendingPathComponent(checkpoint.archivePath)
                .standardizedFileURL.path
        )
    }

    private func copy(
        _ checkpoint: LegacyMigrationCheckpoint,
        archivePath: String
    ) -> LegacyMigrationCheckpoint {
        LegacyMigrationCheckpoint(
            accountID: checkpoint.accountID,
            vaultID: checkpoint.vaultID,
            migrationID: checkpoint.migrationID,
            archivePath: archivePath,
            uploadedEntryIDs: checkpoint.uploadedEntryIDs,
            uploadedPhotoNames: checkpoint.uploadedPhotoNames,
            verifiedAt: checkpoint.verifiedAt
        )
    }
}
