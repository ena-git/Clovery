import Combine
import Foundation

@MainActor
final class LegacyUpgradeController: ObservableObject {
    static let acknowledgementKey = "clovery_last_upgrade_notice_version"
    static let noticeSchemaKey = "clovery_upgrade_notice_schema_version"
    static let noticeSchemaVersion = 1

    let detector: LegacyDataDetecting
    let currentVersion: String
    private let userDefaults: UserDefaults

    init(
        detector: LegacyDataDetecting,
        currentVersion: String,
        userDefaults: UserDefaults = .standard
    ) {
        self.detector = detector
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
    }

    var hasLegacyData: Bool {
        detector.hasLegacyData
    }

    var hasAcknowledgedNotice: Bool {
        userDefaults.integer(forKey: Self.noticeSchemaKey) >= Self.noticeSchemaVersion
    }

    var hasAcknowledgedCurrentVersion: Bool {
        hasAcknowledgedNotice
    }

    func acknowledgeNotice() {
        userDefaults.set(Self.noticeSchemaVersion, forKey: Self.noticeSchemaKey)
        userDefaults.set(currentVersion, forKey: Self.acknowledgementKey)
    }

    func dismissNotice() {
        acknowledgeNotice()
    }
}

extension LegacyUpgradeController: BootstrapNoticeControlling {}
