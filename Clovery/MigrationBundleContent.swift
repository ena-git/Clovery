import Foundation

struct PreparedMigrationBundle {
    let files: [String: Data]
    let manifest: MigrationBundleManifest
}

struct MigrationBundleContentBuilder {
    private let fileManager: FileManager
    private let documentsDirectory: URL

    init(fileManager: FileManager, documentsDirectory: URL) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
    }

    func prepare(
        entriesJSON: String,
        deletedIDsJSON: String,
        sources: [String]
    ) throws -> PreparedMigrationBundle {
        let entriesData = Data(entriesJSON.utf8)
        guard let entries = try JSONSerialization.jsonObject(with: entriesData)
            as? [[String: Any]] else {
            throw MigrationBundleError.invalidEntriesJSON
        }
        let deletedIDsData = Data(deletedIDsJSON.utf8)
        guard let deletedIDs = try JSONSerialization.jsonObject(with: deletedIDsData)
            as? [String] else {
            throw MigrationBundleError.invalidDeletedIDsJSON
        }

        let entryManifest = try MigrationBundleContentValidator.migrationEntries(in: entries)
        try MigrationBundleContentValidator.validateSources(sources)
        try MigrationBundleContentValidator.validateDeletedIDs(
            deletedIDs,
            activeEntryIDs: Set(entryManifest.map(\.entryID))
        )

        let photosDirectory = documentsDirectory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let availablePhotos = try allPhotoData(in: photosDirectory)
        let referencedPhotos = try referencedPhotoFilenames(in: entries)
        for filename in referencedPhotos where availablePhotos[filename] == nil {
            throw MigrationBundleError.missingPhoto(filename)
        }

        var files: [String: Data] = [
            "entries.json": entriesData,
            "deleted_ids.json": deletedIDsData,
        ]
        var photoManifest: [MigrationPhotoManifest] = []
        for filename in availablePhotos.keys.sorted() {
            guard let data = availablePhotos[filename] else {
                throw MigrationBundleError.missingPhoto(filename)
            }
            files["photos/\(filename)"] = data
            photoManifest.append(
                MigrationPhotoManifest(
                    filename: filename,
                    sha256: MigrationBundleContentValidator.sha256(data),
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
            entriesSHA256: MigrationBundleContentValidator.sha256(entriesData),
            entryCount: entries.count,
            entries: entryManifest,
            deletedIDsFile: "deleted_ids.json",
            deletedIDsSHA256: MigrationBundleContentValidator.sha256(deletedIDsData),
            deletedCount: deletedIDs.count,
            deletedIDs: deletedIDs,
            photos: photoManifest,
            sources: sources
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        files["manifest.json"] = try encoder.encode(manifest)
        return PreparedMigrationBundle(files: files, manifest: manifest)
    }

    private func referencedPhotoFilenames(
        in entries: [[String: Any]]
    ) throws -> Set<String> {
        var filenames: Set<String> = []
        for entry in entries {
            guard let photos = entry["photos"] as? [String] else { continue }
            for photo in photos where !photo.hasPrefix("data:") {
                guard MigrationBundleContentValidator.isValidPhotoFilename(photo) else {
                    throw MigrationBundleError.invalidPhotoFilename(photo)
                }
                filenames.insert(photo)
            }
        }
        return filenames
    }

    private func allPhotoData(in directory: URL) throws -> [String: Data] {
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var photos: [String: Data] = [:]
        for url in urls {
            let filename = url.lastPathComponent
            guard MigrationBundleContentValidator.isValidPhotoFilename(filename),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else {
                continue
            }
            photos[filename] = try Data(contentsOf: url)
        }
        return photos
    }
}
