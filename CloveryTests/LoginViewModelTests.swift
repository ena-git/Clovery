import XCTest
@testable import Clovery

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testInvalidCredentialsUseGenericMessage() async {
        let api = AuthenticationAPISpy()
        api.loginError = .server(
            code: "invalid_credentials",
            message: "Authentication failed.",
            statusCode: 401
        )
        let controller = makeController(api: api)
        let viewModel = LoginViewModel(api: api, sessionController: controller)
        viewModel.loginID = "clovery_user"
        viewModel.password = "eight888"

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "Clovery ID 或密码不正确")
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testDuplicateSubmissionOnlyCallsLoginOnce() async {
        let api = AuthenticationAPISpy()
        api.loginDelayNanoseconds = 100_000_000
        let controller = makeController(api: api)
        let viewModel = LoginViewModel(api: api, sessionController: controller)
        viewModel.loginID = "clovery_user"
        viewModel.password = "eight888"

        async let first: Void = viewModel.submit()
        async let second: Void = viewModel.submit()
        _ = await (first, second)

        XCTAssertEqual(api.loginCallCount, 1)
    }

    private func makeController(api: AuthenticationAPIProtocol) -> ApplicationSessionController {
        ApplicationSessionController(
            api: api,
            sessionStore: AuthenticationSessionStore(
                keychain: KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
            ),
            deviceIdentityStore: DeviceIdentityStore(
                keychain: KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
            )
        )
    }
}
