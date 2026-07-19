import XCTest
@testable import Clovery

final class AuthenticationRoutingTests: XCTestCase {
    func testEntryActionRoutesToLogin() {
        var route = AuthenticationRoute.signUp
        route = .login
        XCTAssertEqual(route, .login)
    }

    func testProviderAccessibilityLabelsAreStable() {
        XCTAssertEqual(AuthenticationProviderKind.apple.accessibilityLabel, "使用 Apple 登录")
        XCTAssertEqual(AuthenticationProviderKind.google.accessibilityLabel, "使用 Google 登录")
        XCTAssertEqual(AuthenticationProviderKind.huawei.accessibilityLabel, "使用华为账号登录")
        XCTAssertEqual(AuthenticationProviderKind.passkey.accessibilityLabel, "使用 Clovery Passkey 登录")
    }
}
