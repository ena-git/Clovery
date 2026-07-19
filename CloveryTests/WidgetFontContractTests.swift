import Foundation
import XCTest

final class WidgetFontContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testWidgetReadsCanonicalFontAndSupportsAllSelections() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "CloveryWidget/CloveryWidget.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("\"clovery_font_selection\""))
        XCTAssertTrue(source.contains("\"NotoSerifSC\""))
        XCTAssertTrue(source.contains("\"NaiChaTi\""))
        XCTAssertTrue(source.contains("\"NotoSerifSC-ExtraLight\""))
        XCTAssertTrue(source.contains("\"BoBoNaiChaTi\""))
    }
}
