import XCTest

final class AccountUpgradeUITests: CloveryUITestCase {
    func testReleaseRoutesPassAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else { return }
        let systemAuditTypes: XCUIAccessibilityAuditType = [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ]

        for route in [
            "authentication",
            "notice",
            "provider-login",
            "identity-claim",
            "migration",
            "entitlement",
            "needs-attention",
            "account-security"
        ] {
            try XCTContext.runActivity(named: route) { _ in
                let application = launch(route: route, accessibilityText: true)
                assertVisible(application.descendants(matching: .any).firstMatch, route: route)
                try application.performAccessibilityAudit(for: systemAuditTypes)
            }
        }
    }

    func testAllReleaseRoutesRenderWithoutCrash() {
        let routes: [(String, (XCUIApplication) -> XCUIElement)] = [
            ("authentication", { $0.buttons["登录"] }),
            ("notice", { $0.staticTexts["欢迎升级 Clovery"] }),
            ("provider-login", { $0.staticTexts["欢迎回来！"] }),
            ("identity-claim", { $0.staticTexts["创建 Clovery 账户"] }),
            ("migration", { $0.staticTexts["正在整理你的 Clovery"] }),
            ("entitlement", {
                $0.descendants(matching: .any)["正在恢复已购权益，进行中"]
            }),
            ("needs-attention", { $0.staticTexts["需要你的协助"] }),
            ("diary", { $0.webViews.firstMatch }),
            ("account-security", {
                $0.descendants(matching: .any)["account-security-screen"]
            })
        ]

        for (route, element) in routes {
            XCTContext.runActivity(named: route) { _ in
                let application = launch(route: route)
                assertVisible(element(application), route: route, timeout: route == "diary" ? 12 : 5)
            }
        }
    }

    func testAccessibilityTextAndFontsKeepPrimaryActionsReachable() {
        for font in ["Gaegu", "System", "NotoSerifSC", "NaiChaTi"] {
            XCTContext.runActivity(named: font) { _ in
                let authentication = launch(
                    route: "authentication",
                    font: font,
                    accessibilityText: true,
                    darkAppearance: true
                )
                assertReachable(
                    authentication.buttons["登录"],
                    route: "authentication-\(font)"
                )

                let reconciliation = launch(
                    route: "needs-attention",
                    font: font,
                    accessibilityText: true,
                    darkAppearance: true
                )
                assertReachable(
                    reconciliation.buttons["重试"],
                    route: "needs-attention-\(font)"
                )
            }
        }
    }

    func testLoginFieldsGrowAtAccessibilityTextSize() {
        let defaultApplication = launch(route: "provider-login")
        let defaultField = defaultApplication.textFields["Clovery ID..."]
        assertVisible(defaultField, route: "provider-login-default")
        let defaultHeight = defaultField.frame.height

        let accessibilityApplication = launch(
            route: "provider-login",
            accessibilityText: true
        )
        let accessibilityField = accessibilityApplication.textFields["Clovery ID..."]
        assertVisible(accessibilityField, route: "provider-login-accessibility")
        XCTAssertGreaterThan(accessibilityField.frame.height, defaultHeight)
    }

    func testAccessibilityRoutesKeepRequiredActionsReachable() {
        let routes: [(String, (XCUIApplication) -> XCUIElement)] = [
            ("authentication", { $0.buttons["登录"] }),
            ("notice", { $0.buttons["我已知晓"] }),
            ("provider-login", { $0.buttons["登录"] }),
            ("identity-claim", { $0.textFields["Clovery ID..."] }),
            ("needs-attention", { $0.buttons["重试"] }),
            ("account-security", { $0.buttons["account-deletion-entry"] })
        ]

        for (route, element) in routes {
            XCTContext.runActivity(named: route) { _ in
                let application = launch(route: route, accessibilityText: true)
                assertReachable(element(application), route: route)
            }
        }
    }

    func testAccountDeletionRequiresExactCloveryID() {
        let application = launch(route: "account-security")
        let deletionEntry = application.buttons["account-deletion-entry"]
        assertVisible(deletionEntry, route: "account-security")
        XCTAssertTrue(deletionEntry.isEnabled)
        deletionEntry.tap()

        let confirmation = application.descendants(matching: .any)["account-deletion-screen"]
        assertVisible(confirmation, route: "account-deletion")
        let submit = application.buttons["account-deletion-confirm-button"]
        XCTAssertFalse(submit.isEnabled)

        let field = application.textFields["account-deletion-confirmation-field"]
        field.tap()
        field.typeText("verification_user")
        XCTAssertTrue(submit.isEnabled)
    }

    func testReconciliationRoutesSurviveRelaunch() {
        for route in ["migration", "entitlement", "needs-attention"] {
            XCTContext.runActivity(named: route) { _ in
                let application = launch(route: route)
                assertVisible(application.staticTexts.firstMatch, route: route)
                application.terminate()
                application.launch()
                assertVisible(application.staticTexts.firstMatch, route: "\(route)-relaunched")
            }
        }
    }

    func testIdentityClaimAndDiarySurviveRelaunch() {
        let routes: [(String, (XCUIApplication) -> XCUIElement)] = [
            ("identity-claim", { $0.staticTexts["创建 Clovery 账户"] }),
            ("diary", { $0.webViews.firstMatch })
        ]

        for (route, element) in routes {
            XCTContext.runActivity(named: route) { _ in
                let application = launch(route: route)
                assertVisible(element(application), route: route, timeout: route == "diary" ? 12 : 5)
                application.terminate()
                application.launch()
                assertVisible(
                    element(application),
                    route: "\(route)-relaunched",
                    timeout: route == "diary" ? 12 : 5
                )
            }
        }
    }

    func testReconciliationSurvivesBackgroundAndForeground() {
        let application = launch(route: "migration")
        let title = application.staticTexts["正在整理你的 Clovery"]
        assertVisible(title, route: "migration-background")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            application.wait(for: .runningBackground, timeout: 5),
            "Migration route did not enter the background"
        )
        application.activate()

        assertVisible(title, route: "migration-foreground")
    }

    func testRetryTransitionsOfflineStateBackToWorking() {
        let application = launch(route: "needs-attention")
        let retry = application.buttons["重试"]
        assertVisible(retry, route: "needs-attention-offline")
        retry.tap()

        assertVisible(
            application.staticTexts["正在整理你的 Clovery"],
            route: "needs-attention-recovered"
        )
    }

    func testReconciliationSupportsReduceMotionAndDarkAppearance() {
        let application = launch(
            route: "migration",
            accessibilityText: true,
            darkAppearance: true,
            reduceMotion: true
        )

        assertVisible(
            application.staticTexts["正在整理你的 Clovery"],
            route: "migration-reduce-motion"
        )
    }
}
