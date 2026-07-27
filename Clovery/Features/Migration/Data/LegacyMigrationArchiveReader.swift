import CryptoKit
import Foundation

struct LegacyMigrationArchiveAsset {
    let filename: String
    let sha256: String
    let bytes: Int64
    let data: Data
}

struct LegacyMigrationArchive {
    let manifest: MigrationBundleManifest
    let manifestData: Data
    let entries: [LegacyMigrationEntryUpload]
    let assets: [LegacyMigrationArchiveAsset]

    func createRequest(migrationID: UUID) -> LegacyMigrationCreateRequest {
        LegacyMigrationCreateRequest(
            migrationID: migrationID,
            formatVersion: manifest.formatVersion,
            source: "v1_bundle",
            entryCount: manifest.entryCount,
            assetCount: manifest.photos.count,
            totalBytes: totalBytes,
            manifestSHA256: Self.sha256(manifestData),
            manifestBase64: manifestData.base64EncodedString()
        )
    }

    var totalBytes: Int64 {
        let entryBytes = manifest.entries.reduce(Int64(0)) { $0 + Int64($1.bytes) }
        let deletionBytes = Int64(manifest.deletedIDs.count * 2)
        let assetBytes = assets.reduce(Int64(0)) { $0 + $1.bytes }
        return entryBytes + deletionBytes + assetBytes
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct LegacyMigrationArchiveReader {
    func read(from archiveURL: URL) throws -> LegacyMigrationArchive {
        try MigrationBundleContentValidator().validateArchive(at: archiveURL)
        let files = try MigrationBundleArchive.read(from: archiveURL)
        guard let manifestData = files["manifest.json"],
              let entriesData = files["entries.json"],
              let manifest = try? JSONDecoder().decode(
                  MigrationBundleManifest.self,
                  from: manifestData
              ),
              let exportedAt = Self.parseDate(manifest.exportedAt),
              let entryObjects = try? JSONSerialization.jsonObject(with: entriesData)
                  as? [[String: Any]] else {
            throw MigrationBundleError.invalidManifest
        }

        let objectsByID = Dictionary(
            uniqueKeysWithValues: entryObjects.compactMap { object in
                (object["id"] as? String).map { ($0, object) }
            }
        )
        var uploads: [LegacyMigrationEntryUpload] = []
        for item in manifest.entries {
            guard let object = objectsByID[item.entryID] else {
                throw MigrationBundleError.invalidManifest
            }
            let payload = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            uploads.append(
                LegacyMigrationEntryUpload(
                    entryID: item.entryID,
                    payload: payload,
                    sha256: item.sha256,
                    deletedAt: nil
                )
            )
        }

        let emptyPayload = Data("{}".utf8)
        let emptySHA = Self.sha256(emptyPayload)
        uploads.append(contentsOf: manifest.deletedIDs.map {
            LegacyMigrationEntryUpload(
                entryID: $0,
                payload: emptyPayload,
                sha256: emptySHA,
                deletedAt: exportedAt
            )
        })

        let assets = try manifest.photos.map { photo in
            guard let data = files["photos/\(photo.filename)"] else {
                throw MigrationBundleError.missingPhoto(photo.filename)
            }
            return LegacyMigrationArchiveAsset(
                filename: photo.filename,
                sha256: photo.sha256,
                bytes: Int64(photo.bytes),
                data: data
            )
        }
        return LegacyMigrationArchive(
            manifest: manifest,
            manifestData: manifestData,
            entries: uploads,
            assets: assets
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
