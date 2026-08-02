import Foundation

@MainActor
protocol LegacyMigrationArchivePreparing: AnyObject {
    func prepare(migrationID: UUID) async throws -> MigrationBundleExportResult
}

@MainActor
final class LegacyMigrationArchivePreparer: LegacyMigrationArchivePreparing {
    private let reader: LegacySnapshotReader
    private let merger: LegacySnapshotMerger
    private let exporter: MigrationBundleExporter

    init(
        reader: LegacySnapshotReader,
        merger: LegacySnapshotMerger = LegacySnapshotMerger(),
        exporter: MigrationBundleExporter = MigrationBundleExporter()
    ) {
        self.reader = reader
        self.merger = merger
        self.exporter = exporter
    }

    func prepare(migrationID: UUID) async throws -> MigrationBundleExportResult {
        let readResult = await reader.readSources()
        if let warning = readResult.warnings.first(where: \.retryable) {
            throw LegacyMigrationArchivePreparationError.sourceUnavailable(warning.code)
        }
        let snapshot = merger.merge(readResult)
        if let warning = snapshot.warnings.first(where: \.retryable) {
            throw LegacyMigrationArchivePreparationError.sourceUnavailable(warning.code)
        }
        guard !snapshot.sources.isEmpty else {
            throw LegacyMigrationArchivePreparationError.noReadableSources
        }
        return try exporter.export(
            migrationID: migrationID,
            entriesJSON: snapshot.entriesJSON,
            deletedIDsJSON: snapshot.deletedIDsJSON,
            sources: snapshot.sources
        )
    }
}

enum LegacyMigrationArchivePreparationError: Error, Equatable {
    case sourceUnavailable(String)
    case noReadableSources
}
