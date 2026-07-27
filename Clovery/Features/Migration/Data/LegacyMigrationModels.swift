import Foundation

enum LegacyMigrationState: String, Codable, Equatable {
    case uploading
    case verified
    case needsAttention = "needs_attention"
}

enum LegacyAssetUploadState: String, Codable, Equatable {
    case uploadRequired = "upload_required"
    case complete
}

struct LegacyMigrationCreateRequest: Equatable, Encodable {
    let migrationID: UUID
    let formatVersion: Int
    let source: String
    let entryCount: Int
    let assetCount: Int
    let totalBytes: Int64
    let manifestSHA256: String
    let manifestBase64: String

    enum CodingKeys: String, CodingKey {
        case migrationID = "migration_id"
        case formatVersion = "format_version"
        case source
        case entryCount = "entry_count"
        case assetCount = "asset_count"
        case totalBytes = "total_bytes"
        case manifestSHA256 = "manifest_sha256"
        case manifestBase64 = "manifest_base64"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(migrationID.uuidString.lowercased(), forKey: .migrationID)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(source, forKey: .source)
        try container.encode(entryCount, forKey: .entryCount)
        try container.encode(assetCount, forKey: .assetCount)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(manifestSHA256, forKey: .manifestSHA256)
        try container.encode(manifestBase64, forKey: .manifestBase64)
    }
}

struct LegacyMigrationEntryUpload: Equatable {
    let entryID: String
    let payload: Data
    let sha256: String
    let deletedAt: Date?
}

struct LegacyMigrationAssetUpload: Equatable {
    let assetID: UUID
    let sourceFilename: String
    let contentType: String
    let byteSize: Int64
    let sha256: String
}

struct LegacyAssetUploadTicket: Equatable, Decodable {
    let assetID: UUID
    let status: LegacyAssetUploadState
    let uploadURL: URL?
    let requiredHeaders: [String: String]
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case status
        case uploadURL = "upload_url"
        case requiredHeaders = "required_headers"
        case expiresAt = "expires_at"
    }

    init(
        assetID: UUID,
        status: LegacyAssetUploadState,
        uploadURL: URL?,
        requiredHeaders: [String: String],
        expiresAt: Date?
    ) {
        self.assetID = assetID
        self.status = status
        self.uploadURL = uploadURL
        self.requiredHeaders = requiredHeaders
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try container.decode(UUID.self, forKey: .assetID)
        status = try container.decode(LegacyAssetUploadState.self, forKey: .status)
        uploadURL = try container.decodeIfPresent(URL.self, forKey: .uploadURL)
        requiredHeaders = try container.decodeIfPresent(
            [String: String].self,
            forKey: .requiredHeaders
        ) ?? [:]
        let rawDate = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        expiresAt = rawDate.flatMap(LegacyMigrationDate.parse)
    }
}

struct LegacyMigrationRemote: Equatable, Decodable {
    let migrationID: UUID
    let status: LegacyMigrationState

    enum CodingKeys: String, CodingKey {
        case migrationID = "migration_id"
        case status
    }
}

struct LegacyMigrationReport: Equatable, Decodable {
    let migrationID: UUID
    let status: LegacyMigrationState
    let expectedEntries: Int
    let importedEntries: Int
    let insertedEntries: Int
    let duplicateEntries: Int
    let conflictCopies: Int
    let expectedDeletedEntries: Int
    let importedDeletedEntries: Int
    let expectedAssets: Int
    let verifiedAssets: Int
    let expectedBytes: Int64
    let verifiedBytes: Int64
    let verifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case migrationID = "migration_id"
        case status
        case expectedEntries = "expected_entries"
        case importedEntries = "imported_entries"
        case insertedEntries = "inserted_entries"
        case duplicateEntries = "duplicate_entries"
        case conflictCopies = "conflict_copies"
        case expectedDeletedEntries = "expected_deleted_entries"
        case importedDeletedEntries = "imported_deleted_entries"
        case expectedAssets = "expected_assets"
        case verifiedAssets = "verified_assets"
        case expectedBytes = "expected_bytes"
        case verifiedBytes = "verified_bytes"
        case verifiedAt = "verified_at"
    }

    init(
        migrationID: UUID,
        status: LegacyMigrationState,
        expectedEntries: Int,
        importedEntries: Int,
        insertedEntries: Int,
        duplicateEntries: Int,
        conflictCopies: Int,
        expectedDeletedEntries: Int,
        importedDeletedEntries: Int,
        expectedAssets: Int,
        verifiedAssets: Int,
        expectedBytes: Int64,
        verifiedBytes: Int64,
        verifiedAt: Date?
    ) {
        self.migrationID = migrationID
        self.status = status
        self.expectedEntries = expectedEntries
        self.importedEntries = importedEntries
        self.insertedEntries = insertedEntries
        self.duplicateEntries = duplicateEntries
        self.conflictCopies = conflictCopies
        self.expectedDeletedEntries = expectedDeletedEntries
        self.importedDeletedEntries = importedDeletedEntries
        self.expectedAssets = expectedAssets
        self.verifiedAssets = verifiedAssets
        self.expectedBytes = expectedBytes
        self.verifiedBytes = verifiedBytes
        self.verifiedAt = verifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        migrationID = try container.decode(UUID.self, forKey: .migrationID)
        status = try container.decode(LegacyMigrationState.self, forKey: .status)
        expectedEntries = try container.decode(Int.self, forKey: .expectedEntries)
        importedEntries = try container.decode(Int.self, forKey: .importedEntries)
        insertedEntries = try container.decode(Int.self, forKey: .insertedEntries)
        duplicateEntries = try container.decode(Int.self, forKey: .duplicateEntries)
        conflictCopies = try container.decode(Int.self, forKey: .conflictCopies)
        expectedDeletedEntries = try container.decode(Int.self, forKey: .expectedDeletedEntries)
        importedDeletedEntries = try container.decode(Int.self, forKey: .importedDeletedEntries)
        expectedAssets = try container.decode(Int.self, forKey: .expectedAssets)
        verifiedAssets = try container.decode(Int.self, forKey: .verifiedAssets)
        expectedBytes = try container.decode(Int64.self, forKey: .expectedBytes)
        verifiedBytes = try container.decode(Int64.self, forKey: .verifiedBytes)
        let rawDate = try container.decodeIfPresent(String.self, forKey: .verifiedAt)
        verifiedAt = rawDate.flatMap(LegacyMigrationDate.parse)
    }
}

private enum LegacyMigrationDate {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
