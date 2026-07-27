import Foundation
import XCTest
@testable import Clovery

final class IOSVerificationFixtureTests: XCTestCase {
    func testParsesOnlyExplicitDebugFixtureArguments() {
        XCTAssertEqual(
            IOSVerificationFixture.resolve(
                arguments: ["Clovery", "-CloveryVerificationFixture", "migration"]
            ),
            .migration
        )
        XCTAssertNil(IOSVerificationFixture.resolve(arguments: ["Clovery"]))
        XCTAssertNil(
            IOSVerificationFixture.resolve(
                arguments: ["Clovery", "-CloveryVerificationFixture", "unknown"]
            )
        )
    }

    func testFixtureMatrixAndFontArgumentsAreStable() {
        XCTAssertEqual(
            Set(IOSVerificationFixture.allCases.map(\.rawValue)),
            Set([
                "authentication",
                "notice",
                "provider-login",
                "identity-claim",
                "migration",
                "entitlement",
                "needs-attention",
                "diary"
            ])
        )
        XCTAssertEqual(
            IOSVerificationFixture.fontSelection(
                arguments: ["Clovery", "-CloveryVerificationFont", "NotoSerifSC"]
            ),
            .notoSerifSC
        )
        XCTAssertEqual(IOSVerificationFixture.fontSelection(arguments: []), .handwriting)
    }

    func testFixtureImplementationIsExcludedFromReleaseCompilation() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Clovery/Application/Verification/IOSVerificationFixture.swift"
            ),
            encoding: .utf8
        )
        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Clovery/ContentView.swift"),
            encoding: .utf8
        )
        let webView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Clovery/WebView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.hasPrefix("#if DEBUG"))
        XCTAssertTrue(source.hasSuffix("#endif\n"))
        XCTAssertTrue(contentView.contains("#if DEBUG"))
        XCTAssertTrue(contentView.contains("IOSVerificationFixture.resolve"))
        XCTAssertTrue(webView.contains("isVerificationFixture"))
        XCTAssertTrue(webView.contains("registersNotificationHandler"))
        XCTAssertTrue(webView.contains("#if DEBUG"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
