import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacySnapshotReaderTests: XCTestCase {
    func testCollectsWebBackupsCompressedKVSCloudKitAndUserDefaults() async throws {
        let fixture = try makeFixture()
        try writeBackup(
            name: "clovery_full_backup.json",
            entriesJSON: #"[{"id":"full"}]"#,
            directory: fixture.documentsDirectory
        )
        try writeBackup(
            name: "clovery_backup.json",
            entriesJSON: #"[{"id":"slim"}]"#,
            directory: fixture.documentsDirectory
        )
        fixture.keyValue.dataValues["clovery_entries_z"] = try compressed(
            #"[{"id":"kvs-compressed"}]"#
        )
        fixture.defaults.set(#"[{"id":"defaults"}]"#, forKey: "clovery_entries")
        fixture.defaults.set("旧用户", forKey: "clovery_name")

        let result = await fixture.reader.readSources()

        XCTAssertEqual(
            Set(result.sources.map(\.kind)),
            Set([
                .webLocalStorage,
                .fullBackup,
                .slimBackup,
                .ubiquitousKeyValue,
                .cloudKit,
                .userDefaults,
            ])
        )
        XCTAssertEqual(fixture.cloud.pullCalls, 1)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testUncompressedKVSIsUsedWhenCompressedValueIsAbsent() async throws {
        let fixture = try makeFixture()
        fixture.keyValue.stringValues["clovery_entries"] = #"[{"id":"plain-kvs"}]"#

        let result = await fixture.reader.readSources()
        let source = try XCTUnwrap(
            result.sources.first { $0.kind == .ubiquitousKeyValue }
        )

        XCTAssertEqual(source.entriesJSON, #"[{"id":"plain-kvs"}]"#)
    }

    func testCloudKitFailureKeepsLocalSourcesAndBecomesRetryableWarning() async throws {
        let fixture = try makeFixture()
        try writeBackup(
            name: "clovery_full_backup.json",
            entriesJSON: #"[{"id":"safe-local"}]"#,
            directory: fixture.documentsDirectory
        )
        fixture.cloud.error = LegacyReaderTestError.cloudUnavailable

        let result = await fixture.reader.readSources()

        XCTAssertTrue(result.sources.contains { $0.kind == .fullBackup })
        XCTAssertFalse(result.sources.contains { $0.kind == .cloudKit })
        XCTAssertTrue(result.warnings.contains {
            $0.source == .cloudKit && $0.retryable
        })
    }

    func testWebReaderUsesOnlyTheApprovedLocalStorageExtractionScript() {
        XCTAssertEqual(
            LegacyWebLocalStorageReader.extractionScript,
            """
            JSON.stringify({
              entries: localStorage.getItem('clovery_entries') || '[]',
              deletedIDs: localStorage.getItem('clovery_deleted_ids') || '[]'
            })
            """
        )
    }

    private func makeFixture() throws -> ReaderFixture {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: documentsDirectory)
        }

        let suiteName = "com.clovery.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let web = LegacyWebSnapshotReaderSpy(
            snapshot: LegacyWebSnapshot(
                entriesJSON: #"[{"id":"web"}]"#,
                deletedIDsJSON: "[]"
            )
        )
        let keyValue = LegacyKeyValueStoreSpy()
        let cloud = LegacyCloudSnapshotPullerSpy(
            entries: [["id": "cloud", "photos": ["cloud-photo.jpg"]]]
        )
        let reader = LegacySnapshotReader(
            documentsDirectory: documentsDirectory,
            userDefaults: defaults,
            keyValueStore: keyValue,
            webReader: web,
            cloudPuller: cloud
        )
        return ReaderFixture(
            reader: reader,
            documentsDirectory: documentsDirectory,
            defaults: defaults,
            keyValue: keyValue,
            cloud: cloud
        )
    }

    private func writeBackup(
        name: String,
        entriesJSON: String,
        directory: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["entries": entriesJSON, "name": "旧用户"]
        )
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func compressed(_ value: String) throws -> Data {
        try (Data(value.utf8) as NSData).compressed(using: .zlib) as Data
    }
}

@MainActor
private struct ReaderFixture {
    let reader: LegacySnapshotReader
    let documentsDirectory: URL
    let defaults: UserDefaults
    let keyValue: LegacyKeyValueStoreSpy
    let cloud: LegacyCloudSnapshotPullerSpy
}

@MainActor
private final class LegacyWebSnapshotReaderSpy: LegacyWebSnapshotReading {
    let snapshot: LegacyWebSnapshot

    init(snapshot: LegacyWebSnapshot) {
        self.snapshot = snapshot
    }

    func readSnapshot() async throws -> LegacyWebSnapshot { snapshot }
}

private final class LegacyKeyValueStoreSpy: LegacyKeyValueReading {
    var dataValues: [String: Data] = [:]
    var stringValues: [String: String] = [:]

    func synchronize() -> Bool { true }
    func data(forKey key: String) -> Data? { dataValues[key] }
    func string(forKey key: String) -> String? { stringValues[key] }
}

@MainActor
private final class LegacyCloudSnapshotPullerSpy: LegacyCloudSnapshotPulling {
    let entries: [[String: Any]]
    var error: Error?
    private(set) var pullCalls = 0

    init(entries: [[String: Any]]) {
        self.entries = entries
    }

    func pullAllLegacyEntries(photosDirectory: URL) async throws -> [[String: Any]] {
        pullCalls += 1
        if let error { throw error }
        return entries
    }
}

private enum LegacyReaderTestError: Error {
    case cloudUnavailable
}
