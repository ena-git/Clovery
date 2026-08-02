import XCTest

class CloveryUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    @discardableResult
    func launch(
        route: String,
        font: String = "System",
        accessibilityText: Bool = false,
        darkAppearance: Bool = false,
        reduceMotion: Bool = false
    ) -> XCUIApplication {
        app?.terminate()
        let application = XCUIApplication()
        application.launchArguments = [
            "-CloveryVerificationFixture", route,
            "-CloveryVerificationFont", font,
            "-CloveryVerificationDynamicType",
            accessibilityText ? "accessibility" : "default",
            "-CloveryVerificationReduceMotion",
            reduceMotion ? "true" : "false",
            "-AppleInterfaceStyle", darkAppearance ? "Dark" : "Light"
        ]
        application.launch()
        app = application
        return application
    }

    func assertVisible(
        _ element: XCUIElement,
        route: String,
        timeout: TimeInterval = 5
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI for route: \(route)")
        XCTAssertEqual(app.state, .runningForeground, "App is not foreground for route: \(route)")
    }

    func assertReachable(
        _ element: XCUIElement,
        route: String,
        maximumSwipes: Int = 5
    ) {
        assertVisible(element, route: route)
        for _ in 0..<maximumSwipes where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Required action is unreachable for route: \(route)")
    }
}
