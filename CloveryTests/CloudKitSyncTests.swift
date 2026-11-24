import CloudKit
import XCTest
@testable import Clovery

final class CloudKitSyncTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testPopulateRecordWritesUpdatedAtTextCountsAndClearsEmptyPhotos() {
        let recordID = CKRecord.ID(recordName: "entry-1")
        let record = CKRecord(recordType: "DiaryEntry", recordID: recordID)
        let entry: [String: Any] = [
            "id": "entry-1",
            "date": "2026-11-24",
            "lucky": "Sunny coffee walk",
            "mood": "lucky",
            "text": "Warm afternoon light",
            "tags": ["coffee", "walk"],
            "createdAt": 1_760_000_000_000.0,
            "updatedAt": 1_760_000_050_000.0,
            "photos": [String](),
        ]

        CloudKitSync.populateRecord(record, from: entry, photosDir: tempDir)

        XCTAssertEqual(record["date"] as? String, "2026-11-24")
        XCTAssertEqual(record["lucky"] as? String, "Sunny coffee walk")
        XCTAssertEqual(record["text"] as? String, "Warm afternoon light")
        XCTAssertEqual(record["tagCount"] as? Int64, 2)
        XCTAssertEqual(record["photoCount"] as? Int64, 0)
        XCTAssertNil(record["photoAssets"])
        XCTAssertNil(record["photoNames"])
        XCTAssertEqual(record["updatedAt"] as? Double, 1_760_000_050_000.0)
        XCTAssertEqual(record["isDeleted"] as? Int64, 0)

        let clearedEntry: [String: Any] = [
            "id": "entry-1",
            "date": "2026-11-24",
            "lucky": "Sunny coffee walk",
            "tags": [String](),
            "photos": [String](),
            "updatedAt": 1_760_000_060_000.0,
        ]
        CloudKitSync.populateRecord(record, from: clearedEntry, photosDir: tempDir)
        XCTAssertNil(record["tags"])
        XCTAssertEqual(record["tagCount"] as? Int64, 0)
    }

    func testRecordToEntryRestoresTombstoneAndZeroCounts() {
        let deletedID = CKRecord.ID(recordName: "entry-deleted")
        let deletedRecord = CKRecord(recordType: "DiaryEntry", recordID: deletedID)
        deletedRecord["isDeleted"] = Int64(1)
        deletedRecord["deletedAt"] = 1_760_000_999_000.0

        let deletedDict = CloudKitSync.recordToEntry(deletedRecord, photosDir: tempDir)
        XCTAssertEqual(deletedDict?["id"] as? String, "entry-deleted")
        XCTAssertEqual(deletedDict?["isDeleted"] as? Bool, true)
        XCTAssertEqual(deletedDict?["deletedAt"] as? Double, 1_760_000_999_000.0)

        let activeID = CKRecord.ID(recordName: "entry-active")
        let activeRecord = CKRecord(recordType: "DiaryEntry", recordID: activeID)
        activeRecord["date"] = "2026-11-24"
        activeRecord["lucky"] = "Cleared tags & photos"
        activeRecord["tagCount"] = Int64(0)
        activeRecord["photoCount"] = Int64(0)
        activeRecord["createdAt"] = 1_760_000_000_000.0
        activeRecord["updatedAt"] = 1_760_000_123_000.0

        let activeDict = CloudKitSync.recordToEntry(activeRecord, photosDir: tempDir)
        XCTAssertEqual(activeDict?["updatedAt"] as? Double, 1_760_000_123_000.0)
        XCTAssertEqual(activeDict?["tags"] as? [String], [])
        XCTAssertEqual(activeDict?["photos"] as? [String], [])
    }

    func testBridgeJavaScriptDeepLinkAndWatchEntriesIncludePendingFallbacks() {
        let linkJS = BridgeJavaScript.deepLink("write")
        XCTAssertTrue(linkJS.contains("__cloveryHandleDeepLink"))
        XCTAssertTrue(linkJS.contains("clovery_deeplink_pending"))

        let watchJS = BridgeJavaScript.watchEntries([[
            "id": "watch-1",
            "date": "2026-11-24",
            "lucky": "From Watch",
        ]])
        XCTAssertTrue(watchJS.contains("__cloveryImportWatchEntries"))
        XCTAssertTrue(watchJS.contains("clovery_watch_pending"))
    }
}
