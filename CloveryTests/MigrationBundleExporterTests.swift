import Foundation
import XCTest
@testable import Clovery

final class MigrationBundleExporterTests: XCTestCase {
    private var documentsDirectory: URL!
    private var exporter: MigrationBundleExporter!

    override func setUpWithError() throws {
        documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: documentsDirectory.appendingPathComponent("photos", isDirectory: true),
            withIntermediateDirectories: true
        )
        exporter = MigrationBundleExporter(documentsDirectory: documentsDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: documentsDirectory)
    }

    func testExportCreatesValidatedZipAndPreservesPreviousExport() throws {
        let photoData = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        try photoData.write(
            to: documentsDirectory.appendingPathComponent("photos/photo-0001.jpg")
        )
        let orphanPhotoData = Data([0xFF, 0xD8, 0x09, 0xFF, 0xD9])
        try orphanPhotoData.write(
            to: documentsDirectory.appendingPathComponent("photos/photo-orphan.jpg")
        )
        let entriesJSON = #"[{"id":"entry-1","photos":["photo-0001.jpg"]}]"#

        let first = try exporter.export(
            entriesJSON: entriesJSON,
            deletedIDsJSON: #"["deleted-entry"]"#
        )
        let files = try MigrationBundleArchive.read(from: first.archiveURL)
        let manifest = try JSONDecoder().decode(
            MigrationBundleManifest.self,
            from: try XCTUnwrap(files["manifest.json"])
        )

        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.entriesFile, "entries.json")
        XCTAssertEqual(
            manifest.entriesSHA256,
            "bf30cf2482941de2820b0d8c8295425ee3cca60ada181dab8f0853f0348263c8"
        )
        XCTAssertEqual(manifest.entryCount, 1)
        XCTAssertEqual(
            manifest.entries,
            [
                MigrationEntryManifest(
                    entryID: "entry-1",
                    sha256: "e820c24b0c04954d58c1fc3434cc358189ac715ec6ea59dac9ba6d4804c6e9b9",
                    bytes: 44
                )
            ]
        )
        XCTAssertEqual(manifest.deletedIDsFile, "deleted_ids.json")
        XCTAssertEqual(
            manifest.deletedIDsSHA256,
            "5734ee2df11a2fe954ef18adb155aa20fbc19d04c6b2ffe4552319f5e5679306"
        )
        XCTAssertEqual(manifest.deletedCount, 1)
        XCTAssertEqual(manifest.deletedIDs, ["deleted-entry"])
        XCTAssertEqual(manifest.photos.count, 2)
        XCTAssertEqual(files["entries.json"], entriesJSON.data(using: .utf8))
        XCTAssertEqual(files["deleted_ids.json"], #"["deleted-entry"]"#.data(using: .utf8))
        XCTAssertEqual(files["photos/photo-0001.jpg"], photoData)
        XCTAssertEqual(files["photos/photo-orphan.jpg"], orphanPhotoData)
        XCTAssertNoThrow(try exporter.validateArchive(at: first.archiveURL))
        XCTAssertEqual(first.archiveURL.lastPathComponent, "migration_bundle.zip")
        XCTAssertEqual(
            first.archiveURL.deletingLastPathComponent().lastPathComponent,
            first.migrationID
        )

        let second = try exporter.export(entriesJSON: entriesJSON)
        XCTAssertNotEqual(first.archiveURL, second.archiveURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.archiveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.archiveURL.path))
    }

    func testExportRejectsMissingPhotoWithoutDeletingPreviousBundle() throws {
        let validEntries = #"[{"id":"entry-1","photos":[]}]"#
        let previous = try exporter.export(entriesJSON: validEntries)
        let missingPhotoEntries = #"[{"id":"entry-2","photos":["missing.jpg"]}]"#

        XCTAssertThrowsError(try exporter.export(entriesJSON: missingPhotoEntries))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.archiveURL.path))
    }

    func testExportRejectsNonArrayJSON() {
        XCTAssertThrowsError(try exporter.export(entriesJSON: #"{"id":"entry-1"}"#))
    }

    func testExportRejectsInvalidDeletedIDsJSON() {
        XCTAssertThrowsError(
            try exporter.export(
                entriesJSON: "[]",
                deletedIDsJSON: #"{"id":"deleted-entry"}"#
            )
        )
    }

    func testValidationRejectsPhotoHashMismatch() throws {
        let photoURL = documentsDirectory.appendingPathComponent("photos/photo-0001.jpg")
        try Data([1, 2, 3]).write(to: photoURL)
        let result = try exporter.export(
            entriesJSON: #"[{"id":"entry-1","photos":["photo-0001.jpg"]}]"#
        )
        var files = try MigrationBundleArchive.read(from: result.archiveURL)
        files["photos/photo-0001.jpg"] = Data([9, 9, 9])
        let tamperedURL = documentsDirectory.appendingPathComponent("tampered.zip")
        try MigrationBundleArchive.write(files: files, to: tamperedURL)

        XCTAssertThrowsError(try exporter.validateArchive(at: tamperedURL))
    }

    func testValidationRejectsTamperedEntryContentWithSameCount() throws {
        let result = try exporter.export(
            entriesJSON: #"[{"id":"new-1720000000000","text":"original"}]"#
        )
        var files = try MigrationBundleArchive.read(from: result.archiveURL)
        files["entries.json"] = #"[{"id":"new-1720000000000","text":"tampered"}]"#
            .data(using: .utf8)
        let tamperedURL = documentsDirectory.appendingPathComponent("tampered-entry.zip")
        try MigrationBundleArchive.write(files: files, to: tamperedURL)

        XCTAssertThrowsError(try exporter.validateArchive(at: tamperedURL))
    }

    func testExportRejectsDuplicateEntryIDs() {
        XCTAssertThrowsError(
            try exporter.export(
                entriesJSON: #"[{"id":"new-1"},{"id":"new-1"}]"#
            )
        )
    }

    func testExportRejectsDeletedIDThatIsStillActive() {
        XCTAssertThrowsError(
            try exporter.export(
                entriesJSON: #"[{"id":"new-1"}]"#,
                deletedIDsJSON: #"["new-1"]"#
            )
        )
    }

    func testExportRejectsEmptySources() {
        XCTAssertThrowsError(
            try exporter.export(entriesJSON: "[]", sources: [])
        )
    }
}
