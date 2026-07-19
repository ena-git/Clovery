import Foundation
import XCTest
@testable import Clovery

final class AuthenticationReleaseConfigurationTests: XCTestCase {
    func testDebugAcceptsLocalDevelopmentAPI() throws {
        let configuration = APIConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8080")!
        )

        XCTAssertNoThrow(try configuration.validate(for: .debug))
    }

    func testReleaseRejectsNonHTTPSAPI() {
        let configuration = APIConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8080")!
        )

        XCTAssertThrowsError(try configuration.validate(for: .release))
    }

    func testReleaseRejectsStagingAPI() {
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://staging.api.clovery.example")!
        )

        XCTAssertThrowsError(try configuration.validate(for: .release))
    }

    func testReleaseEnvironmentProvidesVerifiedAPIURL() throws {
        let rawURL = ProcessInfo.processInfo.environment["CLOVERY_RELEASE_API_BASE_URL"] ?? ""
        XCTAssertFalse(
            rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Release verification requires CLOVERY_RELEASE_API_BASE_URL."
        )
        let configuration = try APIConfiguration(
            baseURL: XCTUnwrap(URL(string: rawURL))
        )
        XCTAssertNoThrow(try configuration.validate(for: .release))
    }

    func testUnconfiguredWebProviderIsUnavailable() {
        XCTAssertNil(
            WebAuthenticationConfiguration.current(
                provider: .google,
                bundle: Bundle(for: Self.self)
            )
        )
    }
}
