import Foundation

struct VaultDiarySnapshot: Equatable {
    var entries: [[String: JSONValue]]
    var deletedIDs: [String]
    var name: String?

    static let empty = VaultDiarySnapshot(entries: [], deletedIDs: [], name: nil)
}

protocol VaultLocalStoring {
    func load() throws -> VaultDiarySnapshot
    func save(_ snapshot: VaultDiarySnapshot) throws
    func materialize(_ changes: [VaultSyncChange]) throws -> VaultDiarySnapshot
}

enum VaultLocalStoreError: Error {
    case invalidBackup
    case invalidEntryPayload
}

final class VaultLocalStore: VaultLocalStoring {
    private let backupURL: URL
    private let fileManager: FileManager
    private let fileStore: AtomicJSONFileStore
    private let now: () -> Date

    init(
        documentsDirectory: URL,
        namespace: VaultSyncNamespace? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        let backupDirectory: URL
        if let namespace {
            backupDirectory = documentsDirectory
                .appendingPathComponent("Vaults", isDirectory: true)
                .appendingPathComponent(namespace.storageKey, isDirectory: true)
        } else {
            backupDirectory = documentsDirectory
        }
        self.backupURL = backupDirectory.appendingPathComponent("clovery_full_backup.json")
        self.fileManager = fileManager
        self.fileStore = AtomicJSONFileStore(fileManager: fileManager)
        self.now = now
    }

    func load() throws -> VaultDiarySnapshot {
        guard fileManager.fileExists(atPath: backupURL.path) else { return .empty }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: backupURL))
        guard let backup = object as? [String: Any] else {
            throw VaultLocalStoreError.invalidBackup
        }
        return VaultDiarySnapshot(
            entries: try decodeEntries(backup["entries"]),
            deletedIDs: try decodeDeletedIDs(backup["deletedIDs"] ?? backup["deleted_ids"]),
            name: backup["name"] as? String
        )
    }

    func save(_ snapshot: VaultDiarySnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let entries = String(decoding: try encoder.encode(snapshot.entries), as: UTF8.self)
        let deletedIDs = String(decoding: try encoder.encode(snapshot.deletedIDs), as: UTF8.self)
        try fileStore.write(
            VaultBackupEnvelope(
                entries: entries,
                deletedIDs: deletedIDs,
                name: snapshot.name,
                timestamp: now().timeIntervalSince1970
            ),
            to: backupURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    func materialize(_ changes: [VaultSyncChange]) throws -> VaultDiarySnapshot {
        var snapshot = try load()
        var entriesByID = Dictionary(
            uniqueKeysWithValues: snapshot.entries.compactMap { entry in
                entry.stringValue(for: "id").map { ($0, entry) }
            }
        )
        var anonymousEntries = snapshot.entries.filter { $0.stringValue(for: "id") == nil }
        var deletedIDs = Set(snapshot.deletedIDs)

        for change in changes.sorted(by: { $0.cursor < $1.cursor })
        where change.entityType == "journal_entry" {
            if change.deleted {
                entriesByID.removeValue(forKey: change.entityID)
                deletedIDs.insert(change.entityID)
                continue
            }
            guard case let .object(rawPayload) = change.payload else {
                throw VaultLocalStoreError.invalidEntryPayload
            }
            var payload = rawPayload
            payload["id"] = .string(change.entityID)
            if entriesByID[change.entityID] == nil {
                removeLegacyDuplicate(of: payload, from: &entriesByID, anonymousEntries: &anonymousEntries)
            }
            entriesByID[change.entityID] = payload
            deletedIDs.remove(change.entityID)
        }

        snapshot.entries = entriesByID.values.sorted(by: Self.entryOrder) + anonymousEntries
        snapshot.deletedIDs = deletedIDs.sorted()
        try save(snapshot)
        return snapshot
    }

    private func decodeEntries(_ value: Any?) throws -> [[String: JSONValue]] {
        guard let value else { return [] }
        let data = try data(from: value)
        do {
            return try JSONDecoder().decode([[String: JSONValue]].self, from: data)
        } catch {
            throw VaultLocalStoreError.invalidBackup
        }
    }

    private func decodeDeletedIDs(_ value: Any?) throws -> [String] {
        guard let value else { return [] }
        let data = try data(from: value)
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw VaultLocalStoreError.invalidBackup
        }
    }

    private func data(from value: Any) throws -> Data {
        if let string = value as? String, let data = string.data(using: .utf8) {
            return data
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            throw VaultLocalStoreError.invalidBackup
        }
        return try JSONSerialization.data(withJSONObject: value)
    }

    private func removeLegacyDuplicate(
        of payload: [String: JSONValue],
        from entriesByID: inout [String: [String: JSONValue]],
        anonymousEntries: inout [[String: JSONValue]]
    ) {
        let signature = Self.legacySignature(payload)
        if let duplicateID = entriesByID.first(where: {
            $0.key != payload.stringValue(for: "id") && Self.legacySignature($0.value) == signature
        })?.key {
            entriesByID.removeValue(forKey: duplicateID)
            return
        }
        if let index = anonymousEntries.firstIndex(where: { Self.legacySignature($0) == signature }) {
            anonymousEntries.remove(at: index)
        }
    }

    private static func legacySignature(_ entry: [String: JSONValue]) -> String {
        var normalized = entry
        normalized.removeValue(forKey: "id")
        normalized.removeValue(forKey: "clovery_asset_refs")
        return (try? VaultPayloadHash.make(.object(normalized))) ?? ""
    }

    private static func entryOrder(
        _ lhs: [String: JSONValue],
        _ rhs: [String: JSONValue]
    ) -> Bool {
        (lhs.stringValue(for: "id") ?? "") < (rhs.stringValue(for: "id") ?? "")
    }
}

private struct VaultBackupEnvelope: Encodable {
    let entries: String
    let deletedIDs: String
    let name: String?
    let timestamp: TimeInterval

    enum CodingKeys: String, CodingKey {
        case entries
        case deletedIDs
        case name
        case timestamp = "ts"
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(for key: String) -> String? {
        guard case let .string(value) = self[key] else { return nil }
        return value
    }
}
