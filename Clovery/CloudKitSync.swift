import CloudKit
import Foundation

/// Syncs diary entries (text + photos) across a user's own devices via their
/// private CloudKit database. Apple manages storage against the user's own
/// iCloud quota — we never see or store this data ourselves.
///
/// Design notes:
/// - Each entry maps to one CKRecord, keyed by the entry's existing local id
///   (`CKRecord.ID(recordName: id)`), so pushing the same entry twice from two
///   devices naturally converges instead of creating duplicates.
/// - Saves use `.changedKeys` so a device that doesn't have an entry's photos
///   yet (e.g. hasn't finished downloading them) can push a text edit without
///   wiping the photos already on the server — only fields we explicitly set
///   are touched.
/// - Deletions are NOT propagated. An entry removed on one device just stops
///   being pushed; its CloudKit record is left alone. This matches the rest
///   of the app's "never destroy data based on a remote signal" philosophy.
@MainActor
class CloudKitSync {
    static let shared = CloudKitSync()

    private let container = CKContainer(identifier: "iCloud.com.clovery.app")
    private lazy var db = container.privateCloudDatabase
    private let recordType = "DiaryEntry"
    private let subscriptionID = "clovery-diary-entry-changes"

    /// Registers a CKQuerySubscription (once) so other devices' writes trigger
    /// a silent push to this device instead of only syncing on next launch.
    func setupSubscriptionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "clovery_ck_subscribed") else { return }

        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        db.save(subscription) { _, error in
            if let error = error {
                print("[Clovery CloudKit] subscription setup failed: \\(error.localizedDescription)")
            } else {
                defaults.set(true, forKey: "clovery_ck_subscribed")
            }
        }
    }

    /// Pushes one entry (text + tags + any photos already on disk) to CloudKit.
    /// `entry` is the decoded JSON dict for a single diary entry; `photosDir`
    /// is the Documents/photos directory the photo-file refactor already writes to.
    func pushEntry(_ entry: [String: Any], photosDir: URL) {
        guard let id = entry["id"] as? String, !id.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record["date"] = entry["date"] as? String
        record["lucky"] = entry["lucky"] as? String
        record["mood"] = entry["mood"] as? String
        record["tags"] = entry["tags"] as? [String]
        if let createdAt = entry["createdAt"] as? Double {
            record["createdAt"] = createdAt
        }

        if let photoNames = entry["photos"] as? [String], !photoNames.isEmpty {
            let assets: [CKAsset] = photoNames.compactMap { name in
                let url = photosDir.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: url.path) ? CKAsset(fileURL: url) : nil
            }
            if !assets.isEmpty {
                record["photoAssets"] = assets
                record["photoNames"] = photoNames
            }
        }

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.modifyRecordsResultBlock = { result in
            if case .failure(let error) = result {
                print("[Clovery CloudKit] push failed for \\(id): \\(error.localizedDescription)")
            }
        }
        db.add(op)
    }

    /// Fetches every DiaryEntry record, downloads any photo assets into
    /// `photosDir` (skipping files that already exist locally), and returns
    /// plain JSON-compatible entry dicts ready to merge in on the JS side.
    func pullAll(photosDir: URL, completion: @escaping ([[String: Any]]) -> Void) {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var results: [[String: Any]] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result,
               let entry = self.recordToEntry(record, photosDir: photosDir) {
                results.append(entry)
            }
        }
        operation.queryResultBlock = { result in
            if case .failure(let error) = result {
                print("[Clovery CloudKit] pull failed: \\(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(results) }
        }
        db.add(operation)
    }

    private func recordToEntry(_ record: CKRecord, photosDir: URL) -> [String: Any]? {
        var entry: [String: Any] = [:]
        entry["id"] = record.recordID.recordName
        entry["date"] = (record["date"] as? String) ?? ""
        entry["lucky"] = (record["lucky"] as? String) ?? ""
        entry["mood"] = (record["mood"] as? String) ?? "lucky"
        entry["tags"] = (record["tags"] as? [String]) ?? []
        if let createdAt = record["createdAt"] as? Double { entry["createdAt"] = createdAt }

        if let assets = record["photoAssets"] as? [CKAsset],
           let names = record["photoNames"] as? [String] {
            var savedNames: [String] = []
            for (i, asset) in assets.enumerated() where i < names.count {
                guard let sourceURL = asset.fileURL else { continue }
                let destName = names[i]
                let destURL = photosDir.appendingPathComponent(destName)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
                savedNames.append(destName)
            }
            if !savedNames.isEmpty { entry["photos"] = savedNames }
        }
        return entry
    }
}
