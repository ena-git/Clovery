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

    func testAccessibilityCategoryScalesLargerThanLargeCategory() {
        let resolver = CloveryFontResolver()

        let large = resolver.uiFont(
            for: .system,
            role: .body,
            contentSizeCategory: .large
        )
        let accessibility = resolver.uiFont(
            for: .system,
            role: .body,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        XCTAssertGreaterThan(accessibility.pointSize, large.pointSize)
    }

    func testHandwritingUsesLanguageSpecificPrimaryFont() {
        let cases = [
            (languageCode: "zh", expectedName: "YLHZYS"),
            (languageCode: "ja", expectedName: "Yomogi-Regular"),
            (languageCode: "en", expectedName: "Gaegu-Regular"),
        ]

        for testCase in cases {
            var requestedNames: [String] = []
            let resolver = CloveryFontResolver(
                languageCode: testCase.languageCode,
                loadFont: { name, size in
                    requestedNames.append(name)
                    return UIFont.systemFont(ofSize: size)
                }
            )

            _ = resolver.uiFont(for: .handwriting, role: .body)

            XCTAssertEqual(
                requestedNames.first,
                testCase.expectedName,
                "Unexpected primary font for \(testCase.languageCode)"
            )
        }
    }

    func testMissingPrimaryFontDoesNotPromoteCascadeFont() throws {
        let fallbackFont = try XCTUnwrap(UIFont(name: "YLHZYS", size: 24))
        let resolver = CloveryFontResolver(
            languageCode: "zh",
            loadFont: { name, _ in
                name == "YLHZYS" ? fallbackFont : nil
            }
        )

        let resolved = resolver.uiFont(for: .naiChaTi, role: .body)

        XCTAssertNotEqual(fallbackFont.familyName, UIFont.systemFont(ofSize: 24).familyName)
        XCTAssertEqual(resolved.familyName, UIFont.systemFont(ofSize: 24).familyName)
    }
}
