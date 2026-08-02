import CryptoKit
import Foundation

struct MigrationBundleContentValidator {
    private static let photoFilenamePattern = #"^[A-Za-z0-9-]+\.jpg$"#
    private static let entryIDPattern = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#

    func validateArchive(at archiveURL: URL) throws {
        let files = try MigrationBundleArchive.read(from: archiveURL)
        guard let manifestData = files["manifest.json"],
              let entriesData = files["entries.json"],
              let deletedData = files["deleted_ids.json"],
              let manifest = try? JSONDecoder().decode(
                  MigrationBundleManifest.self,
                  from: manifestData
              ),
              manifest.formatVersion == 1,
              manifest.entriesFile == "entries.json",
              manifest.deletedIDsFile == "deleted_ids.json",
              let entries = try? JSONSerialization.jsonObject(with: entriesData)
                  as? [[String: Any]],
              let deletedIDs = try? JSONSerialization.jsonObject(with: deletedData)
                  as? [String] else {
            throw MigrationBundleError.invalidManifest
        }
        guard Self.sha256(entriesData) == manifest.entriesSHA256 else {
            throw MigrationBundleError.entriesHashMismatch
        }
        guard Self.sha256(deletedData) == manifest.deletedIDsSHA256 else {
            throw MigrationBundleError.deletedIDsHashMismatch
        }
        guard entries.count == manifest.entryCount else {
            throw MigrationBundleError.entryCountMismatch
        }
        guard deletedIDs.count == manifest.deletedCount,
              deletedIDs == manifest.deletedIDs else {
            throw MigrationBundleError.invalidManifest
        }
        let rebuilt = try Self.migrationEntries(in: entries)
        guard rebuilt == manifest.entries else {
            throw MigrationBundleError.invalidManifest
        }
        try Self.validateDeletedIDs(
            deletedIDs,
            activeEntryIDs: Set(rebuilt.map(\.entryID))
        )
        try Self.validateSources(manifest.sources)
        try validatePhotos(manifest.photos, files: files)
    }

    func matches(
        existingFiles: [String: Data],
        prepared: PreparedMigrationBundle
    ) throws -> Bool {
        let existingKeys = Set(existingFiles.keys).subtracting(["manifest.json"])
        let preparedKeys = Set(prepared.files.keys).subtracting(["manifest.json"])
        guard existingKeys == preparedKeys else { return false }
        for key in preparedKeys where existingFiles[key] != prepared.files[key] {
            return false
        }
        guard let manifestData = existingFiles["manifest.json"],
              let existing = try? JSONDecoder().decode(
                  MigrationBundleManifest.self,
                  from: manifestData
              ) else {
            return false
        }
        return existing.hasSameContent(as: prepared.manifest)
    }

    static func migrationEntries(
        in entries: [[String: Any]]
    ) throws -> [MigrationEntryManifest] {
        var seen: Set<String> = []
        return try entries.map { entry in
            guard let entryID = entry["id"] as? String,
                  isValidEntryID(entryID) else {
                throw MigrationBundleError.invalidEntryID(entry["id"] as? String ?? "")
            }
            guard seen.insert(entryID).inserted else {
                throw MigrationBundleError.duplicateEntryID(entryID)
            }
            let canonical = try JSONSerialization.data(
                withJSONObject: entry,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            return MigrationEntryManifest(
                entryID: entryID,
                sha256: sha256(canonical),
                bytes: canonical.count
            )
        }
    }

    static func validateDeletedIDs(
        _ deletedIDs: [String],
        activeEntryIDs: Set<String>
    ) throws {
        var seen: Set<String> = []
        for entryID in deletedIDs {
            guard isValidEntryID(entryID) else {
                throw MigrationBundleError.invalidEntryID(entryID)
            }
            guard seen.insert(entryID).inserted else {
                throw MigrationBundleError.duplicateEntryID(entryID)
            }
            guard !activeEntryIDs.contains(entryID) else {
                throw MigrationBundleError.activeEntryMarkedDeleted(entryID)
            }
        }
    }

    static func validateSources(_ sources: [String]) throws {
        var seen: Set<String> = []
        for source in sources {
            guard !source.isEmpty,
                  source.trimmingCharacters(in: .whitespacesAndNewlines) == source,
                  seen.insert(source).inserted else {
                throw MigrationBundleError.invalidSource(source)
            }
        }
        guard !seen.isEmpty else {
            throw MigrationBundleError.invalidSource("")
        }
    }

    static func isValidPhotoFilename(_ value: String) -> Bool {
        value.range(of: photoFilenamePattern, options: .regularExpression) != nil
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidEntryID(_ value: String) -> Bool {
        value.range(of: entryIDPattern, options: .regularExpression) != nil
    }

    private func validatePhotos(
        _ photos: [MigrationPhotoManifest],
        files: [String: Data]
    ) throws {
        var seen: Set<String> = []
        for photo in photos {
            guard seen.insert(photo.filename).inserted else {
                throw MigrationBundleError.invalidManifest
            }
            guard let data = files["photos/\(photo.filename)"] else {
                throw MigrationBundleError.missingPhoto(photo.filename)
            }
            guard data.count == photo.bytes else {
                throw MigrationBundleError.photoSizeMismatch(photo.filename)
            }
            guard Self.sha256(data) == photo.sha256 else {
                throw MigrationBundleError.photoHashMismatch(photo.filename)
            }
        }
    }
}

private extension MigrationBundleManifest {
    func hasSameContent(as other: MigrationBundleManifest) -> Bool {
        formatVersion == other.formatVersion &&
            entriesFile == other.entriesFile &&
            entriesSHA256 == other.entriesSHA256 &&
            entryCount == other.entryCount &&
            entries == other.entries &&
            deletedIDsFile == other.deletedIDsFile &&
            deletedIDsSHA256 == other.deletedIDsSHA256 &&
            deletedCount == other.deletedCount &&
            deletedIDs == other.deletedIDs &&
            photos == other.photos &&
            sources == other.sources
    }
}
