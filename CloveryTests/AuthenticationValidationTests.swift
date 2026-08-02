import XCTest
@testable import Clovery

final class AuthenticationValidationTests: XCTestCase {
    func testCloveryIDNormalizesToLowercase() {
        XCTAssertEqual(
            AuthenticationValidation.normalizedCloveryID("  Clovery_User "),
            "clovery_user"
        )
    }

    func testCloveryIDRejectsEmailAddress() {
        XCTAssertFalse(AuthenticationValidation.isValidCloveryID("user@example.com"))
    }

    func testEightCharacterPasswordIsValid() {
        XCTAssertTrue(AuthenticationValidation.isValidPassword("eight888"))
    }

    func testSevenCharacterPasswordIsInvalid() {
        XCTAssertFalse(AuthenticationValidation.isValidPassword("seven77"))
    }
}
