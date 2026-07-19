import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacyDataDetectorTests: XCTestCase {
    func testDetectsLegacyUserDefaultsMarkerWithoutReadingDiaryContents() {
        let suiteName = "com.clovery.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data(), forKey: "clovery_entries_z")

        let detector = LegacyDataDetector(
            userDefaults: defaults,
            fileManager: .default,
            documentsDirectory: FileManager.default.temporaryDirectory,
            cloudKitMarkerProvider: { false }
        )

        XCTAssertTrue(detector.hasLegacyData)
    }

    func testDetectsLegacyBackupFileAndCloudKitMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clovery-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try Data("opaque backup".utf8).write(
            to: directory.appendingPathComponent("clovery_full_backup.json")
        )
        let detector = LegacyDataDetector(
            userDefaults: UserDefaults(suiteName: "com.clovery.tests.\(UUID().uuidString)")!,
            fileManager: .default,
            documentsDirectory: directory,
            cloudKitMarkerProvider: { true }
        )

        XCTAssertTrue(detector.hasLegacyData)
    }
}
