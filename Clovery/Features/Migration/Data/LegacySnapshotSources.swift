import Foundation

enum LegacySnapshotSourceKind: String, Codable, CaseIterable, Equatable {
    case webLocalStorage = "web_local_storage"
    case fullBackup = "documents_full_backup"
    case slimBackup = "documents_slim_backup"
    case ubiquitousKeyValue = "icloud_key_value"
    case cloudKit = "cloudkit"
    case userDefaults = "user_defaults"

    var mergePriority: Int {
        switch self {
        case .fullBackup: 0
        case .webLocalStorage: 1
        case .cloudKit: 2
        case .ubiquitousKeyValue: 3
        case .slimBackup: 4
        case .userDefaults: 5
        }
    }
}

struct LegacySnapshotSourceData: Equatable {
    let kind: LegacySnapshotSourceKind
    let entriesJSON: String?
    let deletedIDsJSON: String?
    let name: String?
}

struct LegacySnapshotWarning: Equatable {
    let source: LegacySnapshotSourceKind
    let code: String
    let retryable: Bool
}

struct LegacySnapshotReadResult: Equatable {
    let sources: [LegacySnapshotSourceData]
    let warnings: [LegacySnapshotWarning]
}

protocol LegacyKeyValueReading: AnyObject {
    @discardableResult func synchronize() -> Bool
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
}

extension NSUbiquitousKeyValueStore: LegacyKeyValueReading {}

struct LegacySnapshotSources {
    private let documentsDirectory: URL
    private let userDefaults: UserDefaults
    private let keyValueStore: LegacyKeyValueReading
    private let fileManager: FileManager

    init(
        documentsDirectory: URL,
        userDefaults: UserDefaults = .standard,
        keyValueStore: LegacyKeyValueReading = NSUbiquitousKeyValueStore.default,
        fileManager: FileManager = .default
    ) {
        self.documentsDirectory = documentsDirectory
        self.userDefaults = userDefaults
        self.keyValueStore = keyValueStore
        self.fileManager = fileManager
    }

    func readLocalSources() -> LegacySnapshotReadResult {
        var sources: [LegacySnapshotSourceData] = []
        var warnings: [LegacySnapshotWarning] = []

        readBackup(
            filename: "clovery_full_backup.json",
            kind: .fullBackup,
            sources: &sources,
            warnings: &warnings
        )
        readBackup(
            filename: "clovery_backup.json",
            kind: .slimBackup,
            sources: &sources,
            warnings: &warnings
        )

        _ = keyValueStore.synchronize()
        readKeyValueSource(
            kind: .ubiquitousKeyValue,
            compressed: keyValueStore.data(forKey: "clovery_entries_z"),
            plain: keyValueStore.string(forKey: "clovery_entries"),
            deletedIDs: keyValueStore.string(forKey: "clovery_deleted_ids"),
            name: keyValueStore.string(forKey: "clovery_name"),
            sources: &sources,
            warnings: &warnings
        )
        readKeyValueSource(
            kind: .userDefaults,
            compressed: userDefaults.data(forKey: "clovery_entries_z"),
            plain: userDefaults.string(forKey: "clovery_entries"),
            deletedIDs: userDefaults.string(forKey: "clovery_deleted_ids"),
            name: userDefaults.string(forKey: "clovery_name"),
            sources: &sources,
            warnings: &warnings
        )

        return LegacySnapshotReadResult(sources: sources, warnings: warnings)
    }

    private func readBackup(
        filename: String,
        kind: LegacySnapshotSourceKind,
        sources: inout [LegacySnapshotSourceData],
        warnings: inout [LegacySnapshotWarning]
    ) {
        let url = documentsDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw LegacySnapshotSourceError.invalidBackup
            }
            let entriesJSON = try jsonString(from: object["entries"], defaultValue: "[]")
            let deletedValue = object["deletedIDs"] ?? object["deleted_ids"]
            let deletedIDsJSON = try jsonString(from: deletedValue, defaultValue: "[]")
            sources.append(
                LegacySnapshotSourceData(
                    kind: kind,
                    entriesJSON: entriesJSON,
                    deletedIDsJSON: deletedIDsJSON,
                    name: object["name"] as? String
                )
            )
        } catch {
            warnings.append(
                LegacySnapshotWarning(
                    source: kind,
                    code: "legacy_backup_invalid",
                    retryable: false
                )
            )
        }
    }

    private func readKeyValueSource(
        kind: LegacySnapshotSourceKind,
        compressed: Data?,
        plain: String?,
        deletedIDs: String?,
        name: String?,
        sources: inout [LegacySnapshotSourceData],
        warnings: inout [LegacySnapshotWarning]
    ) {
        var entriesJSON = plain
        if let compressed {
            do {
                let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
                guard let value = String(data: decompressed, encoding: .utf8) else {
                    throw LegacySnapshotSourceError.invalidCompression
                }
                entriesJSON = value
            } catch {
                warnings.append(
                    LegacySnapshotWarning(
                        source: kind,
                        code: "legacy_compressed_entries_invalid",
                        retryable: false
                    )
                )
            }
        }

        guard entriesJSON != nil || deletedIDs != nil || name != nil else { return }
        sources.append(
            LegacySnapshotSourceData(
                kind: kind,
                entriesJSON: entriesJSON,
                deletedIDsJSON: deletedIDs ?? "[]",
                name: name
            )
        )
    }

    private func jsonString(from value: Any?, defaultValue: String) throws -> String {
        guard let value else { return defaultValue }
        if let string = value as? String { return string }
        guard JSONSerialization.isValidJSONObject(value) else {
            throw LegacySnapshotSourceError.invalidBackup
        }
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard let string = String(data: data, encoding: .utf8) else {
            throw LegacySnapshotSourceError.invalidBackup
        }
        return string
    }
}

private enum LegacySnapshotSourceError: Error {
    case invalidBackup
    case invalidCompression
}
