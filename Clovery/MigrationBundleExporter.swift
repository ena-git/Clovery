import Foundation

struct MigrationBundleExporter {
    private let fileManager: FileManager
    private let documentsDirectory: URL
    private let contentBuilder: MigrationBundleContentBuilder

    init(
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil
    ) {
        let resolvedDocuments = documentsDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileManager = fileManager
        self.documentsDirectory = resolvedDocuments
        self.contentBuilder = MigrationBundleContentBuilder(
            fileManager: fileManager,
            documentsDirectory: resolvedDocuments
        )
    }

    func export(
        migrationID: UUID,
        entriesJSON: String,
        deletedIDsJSON: String = "[]",
        sources: [String] = ["localStorage", "documents", "cloudkit"]
    ) throws -> MigrationBundleExportResult {
        let prepared = try contentBuilder.prepare(
            entriesJSON: entriesJSON,
            deletedIDsJSON: deletedIDsJSON,
            sources: sources
        )
        let identifier = migrationID.uuidString.lowercased()
        let exportDirectory = documentsDirectory
            .appendingPathComponent("CloveryMigration", isDirectory: true)
        let finalDirectory = exportDirectory
            .appendingPathComponent(identifier, isDirectory: true)
        let archiveURL = finalDirectory.appendingPathComponent("migration_bundle.zip")

        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: finalDirectory.path) {
            try reuseArchiveIfMatching(at: archiveURL, prepared: prepared)
            return result(
                migrationID: migrationID,
                archiveURL: archiveURL,
                prepared: prepared
            )
        }

        let temporaryDirectory = exportDirectory
            .appendingPathComponent(".\(identifier).tmp", isDirectory: true)
        if fileManager.fileExists(atPath: temporaryDirectory.path) {
            try fileManager.removeItem(at: temporaryDirectory)
        }
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        let temporaryArchiveURL = temporaryDirectory
            .appendingPathComponent("migration_bundle.zip")

        do {
            try MigrationBundleArchive.write(
                files: prepared.files,
                to: temporaryArchiveURL
            )
            try validateArchive(at: temporaryArchiveURL)
            try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }

        return result(
            migrationID: migrationID,
            archiveURL: archiveURL,
            prepared: prepared
        )
    }

    func validateArchive(at archiveURL: URL) throws {
        try MigrationBundleContentValidator().validateArchive(at: archiveURL)
    }

    private func reuseArchiveIfMatching(
        at archiveURL: URL,
        prepared: PreparedMigrationBundle
    ) throws {
        do {
            try validateArchive(at: archiveURL)
            let existing = try MigrationBundleArchive.read(from: archiveURL)
            guard try MigrationBundleContentValidator().matches(
                existingFiles: existing,
                prepared: prepared
            ) else {
                throw MigrationBundleError.archiveContentMismatch
            }
        } catch {
            throw MigrationBundleError.archiveContentMismatch
        }
    }

    private func result(
        migrationID: UUID,
        archiveURL: URL,
        prepared: PreparedMigrationBundle
    ) -> MigrationBundleExportResult {
        MigrationBundleExportResult(
            migrationID: migrationID,
            archiveURL: archiveURL,
            entryCount: prepared.manifest.entryCount,
            photoCount: prepared.manifest.photos.count
        )
    }
}
