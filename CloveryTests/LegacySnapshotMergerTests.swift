import Foundation
import XCTest
@testable import Clovery

final class LegacySnapshotMergerTests: XCTestCase {
    func testSameIDAndCanonicalContentCollapsesToOneEntry() throws {
        let result = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(
                sources: [
                    source(.webLocalStorage, #"[{"id":"entry-1","text":"same"}]"#),
                    source(.fullBackup, #"[{"text":"same","id":"entry-1"}]"#),
                ],
                warnings: []
            )
        )

        XCTAssertEqual(try entries(in: result).count, 1)
    }

    func testDifferentIDsWithSameIdentityFreeContentCollapseToOneEntry() throws {
        let result = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(
                sources: [
                    source(.webLocalStorage, #"[{"id":"web-id","text":"same","tags":["a"]}]"#),
                    source(.cloudKit, #"[{"id":"cloud-id","text":"same","tags":["a"]}]"#),
                ],
                warnings: []
            )
        )

        XCTAssertEqual(try entries(in: result).count, 1)
    }

    func testSameIDWithDifferentContentPreservesBothUsingStableConflictID() throws {
        let sources = [
            source(.cloudKit, #"[{"id":"entry-1","text":"cloud"}]"#),
            source(.fullBackup, #"[{"id":"entry-1","text":"local","photos":["photo-1.jpg"]}]"#),
        ]

        let first = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(sources: sources, warnings: [])
        )
        let second = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(sources: sources.reversed(), warnings: [])
        )
        let firstEntries = try entries(in: first)
        let secondEntries = try entries(in: second)

        XCTAssertEqual(Set(firstEntries.compactMap { $0["id"] as? String }),
                       Set(secondEntries.compactMap { $0["id"] as? String }))
        XCTAssertEqual(firstEntries.count, 2)
        let original = try XCTUnwrap(firstEntries.first { $0["id"] as? String == "entry-1" })
        XCTAssertEqual(original["photos"] as? [String], ["photo-1.jpg"])
        let conflict = try XCTUnwrap(firstEntries.first {
            ($0["id"] as? String)?.hasPrefix("entry-1:conflict:") == true
        })
        XCTAssertEqual(conflict["clovery_legacy_source_id"] as? String, "entry-1")
    }

    func testInvalidSourcePreservesValidSourceAndReportsWarning() throws {
        let result = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(
                sources: [
                    source(.webLocalStorage, "not-json"),
                    source(.fullBackup, #"[{"id":"entry-1","text":"safe"}]"#),
                ],
                warnings: []
            )
        )

        XCTAssertEqual(try entries(in: result).count, 1)
        XCTAssertTrue(result.warnings.contains {
            $0.source == .webLocalStorage && $0.code == "legacy_entries_invalid"
        })
    }

    func testDeletedIDsNeverRemoveAnActiveConflictingRecord() throws {
        let result = LegacySnapshotMerger().merge(
            LegacySnapshotReadResult(
                sources: [
                    LegacySnapshotSourceData(
                        kind: .fullBackup,
                        entriesJSON: #"[{"id":"entry-1","text":"active"}]"#,
                        deletedIDsJSON: #"["entry-1","deleted-only"]"#,
                        name: nil
                    )
                ],
                warnings: []
            )
        )

        XCTAssertEqual(try deletedIDs(in: result), ["deleted-only"])
    }

    private func source(
        _ kind: LegacySnapshotSourceKind,
        _ entriesJSON: String
    ) -> LegacySnapshotSourceData {
        LegacySnapshotSourceData(
            kind: kind,
            entriesJSON: entriesJSON,
            deletedIDsJSON: "[]",
            name: nil
        )
    }

    private func entries(in result: LegacyMergedSnapshot) throws -> [[String: Any]] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.entriesJSON.utf8))
                as? [[String: Any]]
        )
    }

    private func deletedIDs(in result: LegacyMergedSnapshot) throws -> [String] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.deletedIDsJSON.utf8))
                as? [String]
        )
    }
}
