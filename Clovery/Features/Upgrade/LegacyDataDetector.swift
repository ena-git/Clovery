import Foundation

@MainActor
protocol LegacyDataDetecting: AnyObject {
    var hasLegacyData: Bool { get }
}

@MainActor
final class LegacyDataDetector: LegacyDataDetecting {
    private static let userDefaultsMarkers = [
        "clovery_entries",
        "clovery_entries_z",
        "clovery_name"
    ]
    private static let backupFiles = [
        "clovery_full_backup.json",
        "clovery_backup.json"
    ]

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let documentsDirectory: URL?
    private let cloudKitMarkerProvider: @MainActor () -> Bool

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil,
        cloudKitMarkerProvider: @escaping @MainActor () -> Bool = {
            CloudKitSync.shared.hasLegacyKeyValueData()
        }
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory ??
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        self.cloudKitMarkerProvider = cloudKitMarkerProvider
    }

    var hasLegacyData: Bool {
        if Self.userDefaultsMarkers.contains(where: {
            userDefaults.object(forKey: $0) != nil
        }) {
            return true
        }
        if let documentsDirectory,
           Self.backupFiles.contains(where: {
               fileManager.fileExists(
                   atPath: documentsDirectory.appendingPathComponent($0).path
               )
           })
        {
            return true
        }
        return cloudKitMarkerProvider()
    }
}
