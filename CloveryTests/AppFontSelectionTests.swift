import XCTest
@testable import Clovery

final class AppFontSelectionTests: XCTestCase {
    func testRawValuesMatchWebFontSettings() {
        XCTAssertEqual(AppFontSelection.handwriting.rawValue, "Gaegu")
        XCTAssertEqual(AppFontSelection.system.rawValue, "System")
        XCTAssertEqual(AppFontSelection.notoSerifSC.rawValue, "NotoSerifSC")
        XCTAssertEqual(AppFontSelection.naiChaTi.rawValue, "NaiChaTi")
        XCTAssertEqual(
            AppFontSelection.allCases,
            [.handwriting, .system, .notoSerifSC, .naiChaTi]
        )
    }

    func testStoredValueFallsBackToHandwritingForNilEmptyAndUnknownValues() {
        XCTAssertEqual(AppFontSelection(storedValue: nil), .handwriting)
        XCTAssertEqual(AppFontSelection(storedValue: ""), .handwriting)
        XCTAssertEqual(AppFontSelection(storedValue: "UnknownFont"), .handwriting)
    }
}
