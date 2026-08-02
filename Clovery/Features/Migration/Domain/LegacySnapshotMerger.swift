import CryptoKit
import Foundation

struct LegacyMergedSnapshot: Equatable {
    let entriesJSON: String
    let deletedIDsJSON: String
    let sources: [String]
    let warnings: [LegacySnapshotWarning]
    let name: String?
}

struct LegacySnapshotMerger {
    func merge(_ result: LegacySnapshotReadResult) -> LegacyMergedSnapshot {
        var entries: [[String: Any]] = []
        var deletedIDs: Set<String> = []
        var activeIDs: Set<String> = []
        var originalIDs: Set<String> = []
        var contentHashes: Set<String> = []
        var acceptedSources: [String] = []
        var warnings = result.warnings
        var selectedName: String?

        let orderedSources = result.sources.sorted {
            if $0.kind.mergePriority == $1.kind.mergePriority {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.kind.mergePriority < $1.kind.mergePriority
        }

        for source in orderedSources {
            do {
                let sourceEntries = try parseEntries(source.entriesJSON)
                let sourceDeletedIDs = try parseDeletedIDs(source.deletedIDsJSON)
                acceptedSources.append(source.kind.rawValue)
                if selectedName == nil, let name = source.name, !name.isEmpty {
                    selectedName = name
                }

                for entry in sourceEntries {
                    let entryID = try validEntryID(in: entry)
                    let originalID = entry["clovery_legacy_source_id"] as? String ?? entryID
                    let contentHash = try identityFreeHash(entry)
                    guard contentHashes.insert(contentHash).inserted else { continue }

                    var preserved = entry
                    if originalIDs.contains(originalID) {
                        let conflictID = "\(originalID):conflict:\(contentHash.prefix(12))"
                        preserved["id"] = conflictID
                        preserved["clovery_legacy_source_id"] = originalID
                        activeIDs.insert(conflictID)
                    } else {
                        originalIDs.insert(originalID)
                        activeIDs.insert(entryID)
                    }
                    activeIDs.insert(originalID)
                    entries.append(preserved)
                }
                deletedIDs.formUnion(sourceDeletedIDs)
            } catch {
                warnings.append(
                    LegacySnapshotWarning(
                        source: source.kind,
                        code: "legacy_entries_invalid",
                        retryable: false
                    )
                )
            }
        }

        deletedIDs.subtract(activeIDs)
        return LegacyMergedSnapshot(
            entriesJSON: jsonString(entries),
            deletedIDsJSON: jsonString(deletedIDs.sorted()),
            sources: acceptedSources,
            warnings: warnings,
            name: selectedName
        )
    }

    private func parseEntries(_ value: String?) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let entries = try JSONSerialization.jsonObject(with: Data(value.utf8))
            as? [[String: Any]] else {
            throw LegacySnapshotMergeError.invalidEntries
        }
        for entry in entries {
            _ = try validEntryID(in: entry)
        }
        return entries
    }

    private func parseDeletedIDs(_ value: String?) throws -> [String] {
        guard let value else { return [] }
        guard let identifiers = try JSONSerialization.jsonObject(with: Data(value.utf8))
            as? [String],
              identifiers.allSatisfy({ !$0.isEmpty }) else {
            throw LegacySnapshotMergeError.invalidDeletedIDs
        }
        return identifiers
    }

    private func validEntryID(in entry: [String: Any]) throws -> String {
        guard let entryID = entry["id"] as? String, !entryID.isEmpty else {
            throw LegacySnapshotMergeError.invalidEntryID
        }
        return entryID
    }

    private func identityFreeHash(_ entry: [String: Any]) throws -> String {
        var comparable = entry
        comparable.removeValue(forKey: "id")
        comparable.removeValue(forKey: "clovery_legacy_source_id")
        let data = try JSONSerialization.data(
            withJSONObject: comparable,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func jsonString(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private enum LegacySnapshotMergeError: Error {
    case invalidEntries
    case invalidDeletedIDs
    case invalidEntryID
}
