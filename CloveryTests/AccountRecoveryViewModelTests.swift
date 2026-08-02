import XCTest
@testable import Clovery

@MainActor
final class AccountRecoveryViewModelTests: XCTestCase {
    func testRecoveryCodeFlowConsumesCodeBeforeCompletingReset() async {
        let api = AccountRecoveryAPISpy()
        let viewModel = AccountRecoveryViewModel(api: api)
        viewModel.loginID = "clovery_user"
        viewModel.recoveryCode = "one-time-code"
        viewModel.newPassword = "eight888"
        viewModel.confirmPassword = "eight888"

        await viewModel.submit()

        XCTAssertEqual(api.calls, [.consumeRecoveryCode, .completePasswordReset])
        XCTAssertTrue(viewModel.didComplete)
    }
}

@MainActor
private final class AccountRecoveryAPISpy: AccountRecoveryAPIProtocol {
    enum Call: Equatable {
        case consumeRecoveryCode
        case completePasswordReset
    }

    private(set) var calls: [Call] = []

    func consumeRecoveryCode(
        loginID: String,
        recoveryCode: String
    ) async throws -> RecoveryProofResponse {
        calls.append(.consumeRecoveryCode)
        return RecoveryProofResponse(
            resetIntentID: "intent",
            recoveryProof: "proof",
            expiresIn: 600
        )
    }

    func completePasswordReset(
        resetIntentID: String,
        proof: String,
        newPassword: String
    ) async throws {
        calls.append(.completePasswordReset)
    }
}
