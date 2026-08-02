import Foundation
import XCTest

final class GlobalFontPresentationContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAuthenticationAndUpgradeViewsUseDynamicFontRoles() throws {
        let paths = [
            "Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift",
            "Clovery/Features/Authentication/Presentation/LoginView.swift",
            "Clovery/Features/Authentication/Presentation/SignUpView.swift",
            "Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift",
            "Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift",
            "Clovery/Features/Authentication/Presentation/Components/AuthCapsuleField.swift",
            "Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift",
            "Clovery/Features/Upgrade/UpgradeNoticeView.swift",
        ]

        for path in paths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains(".cloveryFont("), path)
            XCTAssertFalse(source.contains(".font(.auth"), path)
        }
    }

    func testFixedAuthenticationFontDefinitionsAreRemoved() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Gaegu-Regular"))
        XCTAssertFalse(source.contains("static let authTitle"))
    }
}
