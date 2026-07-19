import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var loginID = ""
    @Published var password = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSubmitting = false

    private let api: AuthenticationAPIProtocol
    private let sessionController: ApplicationSessionController

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController
    ) {
        self.api = api
        self.sessionController = sessionController
    }

    func submit() async {
        guard !isSubmitting else {
            return
        }
        errorMessage = nil
        let normalizedID = AuthenticationValidation.normalizedCloveryID(loginID)
        guard AuthenticationValidation.isValidCloveryID(normalizedID) else {
            errorMessage = "请输入有效的 Clovery ID"
            return
        }
        guard AuthenticationValidation.isValidPassword(password) else {
            errorMessage = "密码至少需要 8 位"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let device = try sessionController.deviceRegistration()
            let response = try await api.login(
                loginID: normalizedID,
                password: password,
                device: device
            )
            try sessionController.accept(response)
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "网络暂时不可用，请稍后再试"
        }
        if apiError.code == "invalid_credentials" {
            return "Clovery ID 或密码不正确"
        }
        if apiError.code == "rate_limited" {
            return "尝试次数过多，请稍后再试"
        }
        return "登录失败，请稍后再试"
    }
}
