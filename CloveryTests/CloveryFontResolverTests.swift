import UIKit
import XCTest
@testable import Clovery

final class CloveryFontResolverTests: XCTestCase {
    func testNativeFontResourcesAreRegistered() {
        XCTAssertNotNil(UIFont(name: "YLHZYS", size: 16))
        XCTAssertNotNil(UIFont(name: "Yomogi-Regular", size: 16))
        XCTAssertNotNil(UIFont(name: "NotoSerifSC-ExtraLight", size: 16))
        XCTAssertNotNil(UIFont(name: "BoBoNaiChaTi", size: 16))
    }

    func testMissingCustomFontsFallBackToSystemFont() {
        let resolver = CloveryFontResolver(loadFont: { _, _ in nil })

        let resolved = resolver.uiFont(for: .naiChaTi, role: .body)

        XCTAssertEqual(resolved.familyName, UIFont.systemFont(ofSize: 24).familyName)
    }
}
