import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacyUpgradeControllerTests: XCTestCase {
    func testFreshInstallationWithoutSessionStartsAuthentication() {
        let controller = makeController(hasLegacyData: false)
        XCTAssertFalse(controller.hasLegacyData)
        XCTAssertFalse(controller.hasAcknowledgedNotice)
    }

    func testLegacyInstallationWithoutSessionCannotReachDiary() {
        let controller = makeController(hasLegacyData: true)
        XCTAssertTrue(controller.hasLegacyData)
        XCTAssertFalse(controller.hasAcknowledgedNotice)
    }

    func testDismissingNoticeDoesNotDeleteLegacyData() {
        let detector = LegacyDataDetectorSpy(hasLegacyData: true)
        let controller = LegacyUpgradeController(
            detector: detector,
            currentVersion: "1.0.3",
            userDefaults: makeDefaults()
        )

        controller.dismissNotice()

        XCTAssertTrue(detector.hasLegacyData)
        XCTAssertTrue(controller.hasAcknowledgedCurrentVersion)
    }

    func testNoticeAcknowledgementUsesSchemaInsteadOfMarketingVersion() {
        let defaults = makeDefaults()
        let detector = LegacyDataDetectorSpy(hasLegacyData: true)
        let firstController = LegacyUpgradeController(
            detector: detector,
            currentVersion: "1.1.0",
            userDefaults: defaults
        )
        firstController.acknowledgeNotice()

        let hotfixController = LegacyUpgradeController(
            detector: detector,
            currentVersion: "1.1.1",
            userDefaults: defaults
        )

        XCTAssertTrue(hotfixController.hasAcknowledgedNotice)
        XCTAssertEqual(
            defaults.string(forKey: LegacyUpgradeController.acknowledgementKey),
            "1.1.0"
        )
    }

    private func makeController(hasLegacyData: Bool) -> LegacyUpgradeController {
        LegacyUpgradeController(
            detector: LegacyDataDetectorSpy(hasLegacyData: hasLegacyData),
            currentVersion: "1.0.3",
            userDefaults: makeDefaults()
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.clovery.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

@MainActor
private final class LegacyDataDetectorSpy: LegacyDataDetecting {
    var hasLegacyData: Bool

    init(hasLegacyData: Bool) {
        self.hasLegacyData = hasLegacyData
    }
}
