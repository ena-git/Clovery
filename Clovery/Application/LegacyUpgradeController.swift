import Combine
import Foundation

enum ApplicationRoute: Equatable {
    case authentication
    case diary
    case legacyDiaryWithUpgradeNotice
}

@MainActor
final class LegacyUpgradeController: ObservableObject {
    static let acknowledgementKey = "clovery_last_upgrade_notice_version"

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

    var hasAcknowledgedCurrentVersion: Bool {
        userDefaults.string(forKey: Self.acknowledgementKey) == currentVersion
    }

    func route(
        hasSession: Bool,
        hasLegacyData: Bool,
        hasAcknowledgedCurrentVersion: Bool
    ) -> ApplicationRoute {
        if hasSession {
            return .diary
        }
        if hasLegacyData {
            return hasAcknowledgedCurrentVersion
                ? .diary
                : .legacyDiaryWithUpgradeNotice
        }
        return .authentication
    }

    func currentRoute(hasSession: Bool) -> ApplicationRoute {
        route(
            hasSession: hasSession,
            hasLegacyData: hasLegacyData,
            hasAcknowledgedCurrentVersion: hasAcknowledgedCurrentVersion
        )
    }

    func dismissNotice() {
        userDefaults.set(currentVersion, forKey: Self.acknowledgementKey)
    }
}
