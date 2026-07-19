import XCTest
@testable import Clovery

@MainActor
final class SignUpViewModelTests: XCTestCase {
    func testMismatchedConfirmationBlocksRegistration() async {
        let api = AuthenticationAPISpy()
        let controller = makeController(api: api)
        let viewModel = SignUpViewModel(api: api, sessionController: controller)
        viewModel.loginID = "clovery_user"
        viewModel.password = "eight888"
        viewModel.confirmPassword = "different"

        await viewModel.submit()

        XCTAssertEqual(viewModel.validationError, .passwordsDoNotMatch)
        XCTAssertEqual(api.registerCallCount, 0)
    }

    func testSuccessfulRegistrationRequiresRecoveryCodesAcknowledgement() async {
        let api = AuthenticationAPISpy()
        api.registerResponse = AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: ["one", "two", "three", "four", "five", "six", "seven", "eight"]
        )
        let controller = makeController(api: api)
        let viewModel = SignUpViewModel(api: api, sessionController: controller)
        viewModel.loginID = "Clovery_User"
        viewModel.password = "eight888"
        viewModel.confirmPassword = "eight888"

        await viewModel.submit()

        XCTAssertEqual(viewModel.recoveryCodes?.count, 8)
        XCTAssertEqual(viewModel.loginID, "clovery_user")
        XCTAssertEqual(controller.state.requiresRecoveryCodeAcknowledgement, true)
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
