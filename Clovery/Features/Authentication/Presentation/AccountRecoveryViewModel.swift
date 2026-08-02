import Combine
import Foundation

@MainActor
final class AccountRecoveryViewModel: ObservableObject {
    @Published var loginID = ""
    @Published var recoveryCode = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var didComplete = false

    private let api: AccountRecoveryAPIProtocol

    init(api: AccountRecoveryAPIProtocol) {
        self.api = api
    }

    func submit() async {
        guard !isSubmitting, !didComplete else {
            return
        }
        errorMessage = nil

        let normalizedID = AuthenticationValidation.normalizedCloveryID(loginID)
        guard AuthenticationValidation.isValidCloveryID(normalizedID) else {
            errorMessage = "请输入有效的 Clovery ID"
            return
        }
        guard !recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入恢复码"
            return
        }
        guard AuthenticationValidation.isValidPassword(newPassword) else {
            errorMessage = "新密码至少需要 8 位"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let proof = try await api.consumeRecoveryCode(
                loginID: normalizedID,
                recoveryCode: recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await api.completePasswordReset(
                resetIntentID: proof.resetIntentID,
                proof: proof.recoveryProof,
                newPassword: newPassword
            )
            loginID = normalizedID
            recoveryCode = ""
            newPassword = ""
            confirmPassword = ""
            didComplete = true
        } catch let error as APIError {
            if error.code == "invalid_credentials" {
                errorMessage = "Clovery ID 或恢复码无效"
            } else if error.code == "rate_limited" {
                errorMessage = "尝试次数过多，请稍后再试"
            } else {
                errorMessage = "暂时无法重置密码，请稍后再试"
            }
        } catch {
            errorMessage = "网络暂时不可用，请稍后再试"
        }
    }
}
