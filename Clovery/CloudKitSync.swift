import CloudKit
import Foundation

enum CloudKitSyncStatusState: String {
    case syncing
    case synced
    case noAccount
    case restricted
    case temporarilyUnavailable
    case error
}

struct CloudKitPullResult {
    let entries: [[String: Any]]
    let status: CloudKitSyncStatusState
    let errorMessage: String?
}

/// Syncs diary entries (text + tags + photos + deletion tombstones) across a
/// user's own devices via their private CloudKit database.
@MainActor
class CloudKitSync {
    static let shared = CloudKitSync()

    static let accountDidChangeNotification = Notification.Name("CloveryCloudKitAccountDidChange")

    private let isAvailable: () -> Bool
    private lazy var container = CKContainer(identifier: "iCloud.com.clovery.app")
    private lazy var db = container.privateCloudDatabase
    private let recordType = "DiaryEntry"
    private let subscriptionID = "clovery-diary-entry-changes"
    private let subscribedKey = "clovery_ck_subscribed"
    private var accountObserver: NSObjectProtocol?

    init(isAvailable: @escaping () -> Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }) {
        self.isAvailable = isAvailable
        if isAvailable() {
            accountObserver = NotificationCenter.default.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    UserDefaults.standard.set(false, forKey: self.subscribedKey)
                    self.setupSubscriptionIfNeeded()
                    NotificationCenter.default.post(name: Self.accountDidChangeNotification, object: nil)
                }
            }
        }
    }

    deinit {
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
    }

    /// Registers a CKQuerySubscription so other devices' writes or tombstones
    /// trigger a silent push to this device instead of only syncing on launch.
    func setupSubscriptionIfNeeded() {
        guard isAvailable() else { return }
        guard !UserDefaults.standard.bool(forKey: subscribedKey) else { return }

        container.accountStatus { [weak self] status, _ in
            guard let self, status == .available else { return }
            Task { @MainActor in
                let subscription = CKQuerySubscription(
                    recordType: self.recordType,
                    predicate: NSPredicate(value: true),
                    subscriptionID: self.subscriptionID,
                    options: [.firesOnRecordCreation, .firesOnRecordUpdate]
                )
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info

                self.db.save(subscription) { _, error in
                    if let error = error {
                        print("[Clovery CloudKit] subscription setup failed: \(error.localizedDescription)")
                    } else {
                        Task { @MainActor in
                            UserDefaults.standard.set(true, forKey: self.subscribedKey)
                        }
                    }
                }
            }
        }
    }

    /// Pushes entries in batches via CKModifyRecordsOperation to respect
    /// CloudKit's per-operation record limit and avoid request rate limiting.
    func pushEntries(
        _ entries: [[String: Any]],
        photosDir: URL,
        batchSize: Int = 100,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isAvailable() else {
            completion?(false)
            return
        }
        let valid = entries.filter { ($0["id"] as? String)?.isEmpty == false }
        guard !valid.isEmpty else {
            completion?(true)
            return
        }
        let step = max(1, min(batchSize, 200))
        let chunks = stride(from: 0, to: valid.count, by: step).map {
            Array(valid[$0..<min($0 + step, valid.count)])
        }
        sendChunk(chunks, index: 0, photosDir: photosDir, allSucceeded: true, completion: completion)
    }

    private func sendChunk(
        _ chunks: [[[String: Any]]],
        index: Int,
        photosDir: URL,
        allSucceeded: Bool,
        completion: ((Bool) -> Void)?
    ) {
        guard index < chunks.count else {
            DispatchQueue.main.async { completion?(allSucceeded) }
            return
        }
        let records: [CKRecord] = chunks[index].compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: id))
            Self.populateRecord(record, from: entry, photosDir: photosDir)
            return record
        }
        guard !records.isEmpty else {
            sendChunk(chunks, index: index + 1, photosDir: photosDir, allSucceeded: allSucceeded, completion: completion)
            return
        }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.modifyRecordsResultBlock = { [weak self] result in
            let chunkOK: Bool
            switch result {
            case .success:
                chunkOK = true
            case .failure(let error):
                print("[Clovery CloudKit] batch push failed (chunk \(index)): \(error.localizedDescription)")
                chunkOK = false
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    completion?(allSucceeded && chunkOK)
                    return
                }
                self.sendChunk(
                    chunks,
                    index: index + 1,
                    photosDir: photosDir,
                    allSucceeded: allSucceeded && chunkOK,
                    completion: completion
                )
            }
        }
        db.add(op)
    }

    /// Pushes one entry (text + tags + timestamps + photos) to CloudKit.
    func pushEntry(
        _ entry: [String: Any],
        photosDir: URL,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isAvailable() else {
            completion?(false)
            return
        }
        guard let id = entry["id"] as? String, !id.isEmpty else {
            completion?(false)
            return
        }

        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        Self.populateRecord(record, from: entry, photosDir: photosDir)

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async { completion?(true) }
            case .failure(let error):
                print("[Clovery CloudKit] push failed for \(id): \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
        db.add(op)
    }

    /// Propagates an entry deletion as a tombstone record so other devices and
    /// reinstalls do not resurrect deleted entries.
    func deleteEntry(
        id: String,
        deletedAt: Double,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isAvailable() else {
            completion?(false)
            return
        }
        guard !id.isEmpty else {
            completion?(false)
            return
        }

        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["isDeleted"] = Int64(1)
        record["deletedAt"] = deletedAt
        record["updatedAt"] = deletedAt

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                DispatchQueue.main.async { completion?(true) }
            case .failure(let error):
                print("[Clovery CloudKit] delete tombstone failed for \(id): \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
        db.add(op)
    }

    /// Back-compatible helper returning decoded entries array.
    func pullAll(photosDir: URL, completion: @escaping ([[String: Any]]) -> Void) {
        pullAllWithStatus(photosDir: photosDir) { result in
            completion(result.entries)
        }
    }

    /// Fetches every page of DiaryEntry records via CKQueryOperation.Cursor,
    /// downloads missing photo assets into `photosDir`, and reports iCloud status.
    func pullAllWithStatus(
        photosDir: URL,
        completion: @escaping (CloudKitPullResult) -> Void
    ) {
        guard isAvailable() else {
            completion(CloudKitPullResult(entries: [], status: .temporarilyUnavailable, errorMessage: nil))
            return
        }

        container.accountStatus { [weak self] accountStatus, error in
            guard let self else { return }
            if let error {
                print("[Clovery CloudKit] account status failed: \(error.localizedDescription)")
            }
            switch accountStatus {
            case .available:
                Task { @MainActor in
                    try? FileManager.default.createDirectory(
                        at: photosDir,
                        withIntermediateDirectories: true
                    )
                    let query = CKQuery(recordType: self.recordType, predicate: NSPredicate(value: true))
                    let operation = CKQueryOperation(query: query)
                    let collector = RecordCollector()
                    self.runQueryPage(
                        operation,
                        photosDir: photosDir,
                        collector: collector,
                        completion: completion
                    )
                }
            case .noAccount:
                DispatchQueue.main.async {
                    completion(CloudKitPullResult(entries: [], status: .noAccount, errorMessage: nil))
                }
            case .restricted:
                DispatchQueue.main.async {
                    completion(CloudKitPullResult(entries: [], status: .restricted, errorMessage: nil))
                }
            case .couldNotDetermine, .temporarilyUnavailable:
                DispatchQueue.main.async {
                    completion(CloudKitPullResult(
                        entries: [],
                        status: .temporarilyUnavailable,
                        errorMessage: error?.localizedDescription
                    ))
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(CloudKitPullResult(entries: [], status: .temporarilyUnavailable, errorMessage: nil))
                }
            }
        }
    }

    private func runQueryPage(
        _ operation: CKQueryOperation,
        photosDir: URL,
        collector: RecordCollector,
        completion: @escaping (CloudKitPullResult) -> Void
    ) {
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result,
               let entry = Self.recordToEntry(record, photosDir: photosDir) {
                collector.append(entry)
            }
        }
        operation.queryResultBlock = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let cursor):
                if let cursor {
                    let nextOp = CKQueryOperation(cursor: cursor)
                    self.runQueryPage(
                        nextOp,
                        photosDir: photosDir,
                        collector: collector,
                        completion: completion
                    )
                } else {
                    let entries = collector.snapshot()
                    DispatchQueue.main.async {
                        completion(CloudKitPullResult(entries: entries, status: .synced, errorMessage: nil))
                    }
                }
            case .failure(let error):
                print("[Clovery CloudKit] pull failed: \(error.localizedDescription)")
                let entries = collector.snapshot()
                DispatchQueue.main.async {
                    completion(CloudKitPullResult(
                        entries: entries,
                        status: .error,
                        errorMessage: error.localizedDescription
                    ))
                }
            }
        }
        db.add(operation)
    }

    /// Populates a CKRecord from a decoded diary entry dictionary.
    nonisolated static func populateRecord(
        _ record: CKRecord,
        from entry: [String: Any],
        photosDir: URL
    ) {
        record["date"] = entry["date"] as? String
        record["lucky"] = entry["lucky"] as? String
        record["mood"] = entry["mood"] as? String
        record["text"] = entry["text"] as? String
        if let tags = entry["tags"] as? [String], !tags.isEmpty {
            record["tags"] = tags
        } else {
            record["tags"] = nil
        }
        record["tagCount"] = Int64((entry["tags"] as? [String])?.count ?? 0)

        if let createdAt = entry["createdAt"] as? Double {
            record["createdAt"] = createdAt
        }
        let updatedAt = (entry["updatedAt"] as? Double)
            ?? (entry["createdAt"] as? Double)
            ?? (Date().timeIntervalSince1970 * 1000.0)
        record["updatedAt"] = updatedAt
        record["isDeleted"] = Int64(0)

        let photoNames = (entry["photos"] as? [String]) ?? []
        var assets: [CKAsset] = []
        var validNames: [String] = []
        for name in photoNames {
            let url = photosDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                assets.append(CKAsset(fileURL: url))
                validNames.append(name)
            }
        }
        record["photoCount"] = Int64(validNames.count)
        if !assets.isEmpty {
            record["photoAssets"] = assets
            record["photoNames"] = validNames
        } else {
            record["photoAssets"] = nil
            record["photoNames"] = nil
        }
    }

    /// Decodes a CKRecord into a JSON-compatible entry or tombstone dict.
    nonisolated static func recordToEntry(_ record: CKRecord, photosDir: URL) -> [String: Any]? {
        let id = record.recordID.recordName
        if (record["isDeleted"] as? Int64) == 1 {
            let deletedAt = (record["deletedAt"] as? Double)
                ?? (record["updatedAt"] as? Double)
                ?? ((record.modificationDate?.timeIntervalSince1970 ?? 0) * 1000.0)
            return [
                "id": id,
                "isDeleted": true,
                "deletedAt": deletedAt,
                "updatedAt": deletedAt,
            ]
        }

        var entry: [String: Any] = [:]
        entry["id"] = id
        entry["date"] = (record["date"] as? String) ?? ""
        entry["lucky"] = (record["lucky"] as? String) ?? ""
        entry["mood"] = (record["mood"] as? String) ?? "lucky"
        if let text = record["text"] as? String, !text.isEmpty {
            entry["text"] = text
        }

        if let tagCount = record["tagCount"] as? Int64, tagCount == 0 {
            entry["tags"] = [String]()
        } else {
            entry["tags"] = (record["tags"] as? [String]) ?? []
        }

        if let createdAt = record["createdAt"] as? Double {
            entry["createdAt"] = createdAt
        }
        if let updatedAt = record["updatedAt"] as? Double {
            entry["updatedAt"] = updatedAt
        } else if let createdAt = record["createdAt"] as? Double {
            entry["updatedAt"] = createdAt
        } else if let modDate = record.modificationDate {
            entry["updatedAt"] = modDate.timeIntervalSince1970 * 1000.0
        }

        if let photoCount = record["photoCount"] as? Int64, photoCount == 0 {
            entry["photos"] = [String]()
        } else if let assets = record["photoAssets"] as? [CKAsset],
                  let names = record["photoNames"] as? [String] {
            var savedNames: [String] = []
            for (i, asset) in assets.enumerated() where i < names.count {
                guard let sourceURL = asset.fileURL else { continue }
                let destName = names[i]
                let destURL = photosDir.appendingPathComponent(destName)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    do {
                        try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    } catch {
                        print(
                            "[Clovery CloudKit] photo copy failed for \(record.recordID.recordName) "
                            + "(\(destName)): \(error.localizedDescription)"
                        )
                        continue
                    }
                }
                savedNames.append(destName)
            }
            if !savedNames.isEmpty {
                entry["photos"] = savedNames
            }
        }
        return entry
    }
}

private final class RecordCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[String: Any]] = []

    func append(_ entry: [String: Any]) {
        lock.lock()
        items.append(entry)
        lock.unlock()
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        let copy = items
        lock.unlock()
        return copy
    }
}
