import XCTest
@testable import Clovery

final class ProviderVisibilityPolicyTests: XCTestCase {
    func testCrossPlatformQuickProviderMatrix() {
        let policy = ProviderVisibilityPolicy()

        XCTAssertEqual(policy.quickProviders(for: .iOS), [.apple, .google])
        XCTAssertEqual(policy.quickProviders(for: .huaweiHarmony), [.huawei])
        XCTAssertEqual(policy.quickProviders(for: .androidOther), [.google])
    }

    func testEveryPlatformDefaultsToCloveryIDAndExcludesPasskey() {
        let policy = ProviderVisibilityPolicy()

        for platform in ClientPlatform.allCases {
            XCTAssertEqual(policy.defaultMethod(for: platform), .cloveryID)
            XCTAssertFalse(policy.quickProviders(for: platform).contains(.passkey))
        }
    }
}
