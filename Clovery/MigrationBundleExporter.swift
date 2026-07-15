import CryptoKit
import Foundation

struct MigrationBundleExporter {
    private static let photoFilenamePattern = #"^[A-Za-z0-9-]+\.jpg$"#
    private static let entryIDPattern = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#

    private let fileManager: FileManager
    private let documentsDirectory: URL

    init(
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    func export(
        entriesJSON: String,
        deletedIDsJSON: String = "[]",
        sources: [String] = ["localStorage", "documents", "cloudkit"]
    ) throws -> MigrationBundleExportResult {
        let entriesData = Data(entriesJSON.utf8)
        guard let entries = try JSONSerialization.jsonObject(with: entriesData) as? [[String: Any]] else {
            throw MigrationBundleError.invalidEntriesJSON
        }
        let deletedIDsData = Data(deletedIDsJSON.utf8)
        guard let deletedIDs = try JSONSerialization.jsonObject(with: deletedIDsData) as? [String] else {
            throw MigrationBundleError.invalidDeletedIDsJSON
        }
        let entryManifest = try migrationEntries(in: entries)
        try validateSources(sources)
        try validateDeletedIDs(
            deletedIDs,
            activeEntryIDs: Set(entryManifest.map(\.entryID))
        )

        let referencedPhotos = try referencedPhotoFilenames(in: entries)
        let photosDirectory = documentsDirectory.appendingPathComponent("photos", isDirectory: true)
        var files: [String: Data] = [
            "entries.json": entriesData,
            "deleted_ids.json": deletedIDsData,
        ]
        var photoManifest: [MigrationPhotoManifest] = []

        let availablePhotos = try allPhotoData(in: photosDirectory)
        for filename in referencedPhotos where availablePhotos[filename] == nil {
            throw MigrationBundleError.missingPhoto(filename)
        }

        for filename in availablePhotos.keys.sorted() {
            guard let data = availablePhotos[filename] else {
                throw MigrationBundleError.missingPhoto(filename)
            }
            files["photos/\(filename)"] = data
            photoManifest.append(
                MigrationPhotoManifest(
                    filename: filename,
                    sha256: sha256(data),
                    bytes: data.count
                )
            )
        }

        for backupName in ["clovery_full_backup.json", "clovery_backup.json"] {
            let backupURL = documentsDirectory.appendingPathComponent(backupName)
            if fileManager.fileExists(atPath: backupURL.path) {
                files["backups/\(backupName)"] = try Data(contentsOf: backupURL)
            }
        }

        let manifest = MigrationBundleManifest(
            formatVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            entriesFile: "entries.json",
            entriesSHA256: sha256(entriesData),
            entryCount: entries.count,
            entries: entryManifest,
            deletedIDsFile: "deleted_ids.json",
            deletedIDsSHA256: sha256(deletedIDsData),
            deletedCount: deletedIDs.count,
            deletedIDs: deletedIDs,
            photos: photoManifest,
            sources: sources
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        files["manifest.json"] = try encoder.encode(manifest)

        let migrationID = UUID().uuidString.lowercased()
        let exportDirectory = documentsDirectory
            .appendingPathComponent("CloveryMigration", isDirectory: true)
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let temporaryDirectory = exportDirectory
            .appendingPathComponent(".\(migrationID).tmp", isDirectory: true)
        let finalDirectory = exportDirectory
            .appendingPathComponent(migrationID, isDirectory: true)
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        let temporaryArchiveURL = temporaryDirectory
            .appendingPathComponent("migration_bundle.zip")
        let archiveURL = finalDirectory.appendingPathComponent("migration_bundle.zip")

        do {
            try MigrationBundleArchive.write(files: files, to: temporaryArchiveURL)
            try validateArchive(at: temporaryArchiveURL)
            try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }

        return MigrationBundleExportResult(
            migrationID: migrationID,
            archiveURL: archiveURL,
            entryCount: entries.count,
            photoCount: photoManifest.count
        )
    }

    func validateArchive(at archiveURL: URL) throws {
        let files = try MigrationBundleArchive.read(from: archiveURL)
        guard let manifestData = files["manifest.json"],
              let entriesData = files["entries.json"],
              let deletedIDsData = files["deleted_ids.json"],
              let manifest = try? JSONDecoder().decode(
                MigrationBundleManifest.self,
                from: manifestData
              ),
              manifest.formatVersion == 1,
              manifest.entriesFile == "entries.json",
              manifest.deletedIDsFile == "deleted_ids.json",
              let entries = try? JSONSerialization.jsonObject(with: entriesData) as? [[String: Any]],
              let deletedIDs = try? JSONSerialization.jsonObject(with: deletedIDsData) as? [String] else {
            throw MigrationBundleError.invalidManifest
        }
        guard sha256(entriesData) == manifest.entriesSHA256 else {
            throw MigrationBundleError.entriesHashMismatch
        }
        guard sha256(deletedIDsData) == manifest.deletedIDsSHA256 else {
            throw MigrationBundleError.deletedIDsHashMismatch
        }
        guard entries.count == manifest.entryCount else {
            throw MigrationBundleError.entryCountMismatch
        }
        guard deletedIDs.count == manifest.deletedCount else {
            throw MigrationBundleError.invalidManifest
        }
        let rebuiltEntries = try migrationEntries(in: entries)
        guard rebuiltEntries == manifest.entries else {
            throw MigrationBundleError.invalidManifest
        }
        try validateDeletedIDs(
            deletedIDs,
            activeEntryIDs: Set(rebuiltEntries.map(\.entryID))
        )
        guard deletedIDs == manifest.deletedIDs else {
            throw MigrationBundleError.invalidManifest
        }
        try validateSources(manifest.sources)

        var seenPhotos: Set<String> = []
        for photo in manifest.photos {
            guard seenPhotos.insert(photo.filename).inserted else {
                throw MigrationBundleError.invalidManifest
            }
            guard let data = files["photos/\(photo.filename)"] else {
                throw MigrationBundleError.missingPhoto(photo.filename)
            }
            guard data.count == photo.bytes else {
                throw MigrationBundleError.photoSizeMismatch(photo.filename)
            }
            guard sha256(data) == photo.sha256 else {
                throw MigrationBundleError.photoHashMismatch(photo.filename)
            }
        }
    }

    private func migrationEntries(
        in entries: [[String: Any]]
    ) throws -> [MigrationEntryManifest] {
        var seen: Set<String> = []
        return try entries.map { entry in
            guard let entryID = entry["id"] as? String,
                  entryID.range(
                    of: Self.entryIDPattern,
                    options: .regularExpression
                  ) != nil else {
                throw MigrationBundleError.invalidEntryID(
                    entry["id"] as? String ?? ""
                )
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

    private func validateDeletedIDs(
        _ deletedIDs: [String],
        activeEntryIDs: Set<String>
    ) throws {
        var seen: Set<String> = []
        for entryID in deletedIDs {
            guard entryID.range(
                of: Self.entryIDPattern,
                options: .regularExpression
            ) != nil else {
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

    private func validateSources(_ sources: [String]) throws {
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

    private func referencedPhotoFilenames(in entries: [[String: Any]]) throws -> Set<String> {
        var filenames: Set<String> = []
        for entry in entries {
            guard let photos = entry["photos"] as? [String] else { continue }
            for photo in photos where !photo.hasPrefix("data:") {
                guard photo.range(
                    of: Self.photoFilenamePattern,
                    options: .regularExpression
                ) != nil else {
                    throw MigrationBundleError.invalidPhotoFilename(photo)
                }
                filenames.insert(photo)
            }
        }
        return filenames
    }

    private func allPhotoData(in photosDirectory: URL) throws -> [String: Data] {
        guard fileManager.fileExists(atPath: photosDirectory.path) else { return [:] }
        let fileURLs = try fileManager.contentsOfDirectory(
            at: photosDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var photos: [String: Data] = [:]
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            guard filename.range(
                of: Self.photoFilenamePattern,
                options: .regularExpression
            ) != nil,
            try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            photos[filename] = try Data(contentsOf: fileURL)
        }
        return photos
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
