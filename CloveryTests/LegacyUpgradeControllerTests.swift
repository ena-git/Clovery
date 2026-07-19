import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacyUpgradeControllerTests: XCTestCase {
    func testFreshInstallationWithoutSessionStartsAuthentication() {
        let controller = makeController(hasLegacyData: false)

        let route = controller.route(
            hasSession: false,
            hasLegacyData: false,
            hasAcknowledgedCurrentVersion: false
        )

        XCTAssertEqual(route, .authentication)
    }

    func testLegacyInstallationWithoutSessionStillStartsDiary() {
        let controller = makeController(hasLegacyData: true)

        let route = controller.route(
            hasSession: false,
            hasLegacyData: true,
            hasAcknowledgedCurrentVersion: false
        )

        XCTAssertEqual(route, .legacyDiaryWithUpgradeNotice)
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
