import AuthenticationServices
import Foundation

@MainActor
final class AppleAuthenticationProvider: ProviderAuthorizationProviding {
    let isAvailable = true

    private let provider: ASAuthorizationAppleIDProvider
    private let presentationAnchor: @MainActor () -> ASPresentationAnchor
    private var bridge: AuthorizationControllerBridge?

    init(
        provider: ASAuthorizationAppleIDProvider = ASAuthorizationAppleIDProvider(),
        presentationAnchor: @escaping @MainActor () -> ASPresentationAnchor = AuthenticationPresentationAnchor.current
    ) {
        self.provider = provider
        self.presentationAnchor = presentationAnchor
    }

    func authorize(nonce: String) async -> ProviderAuthorizationResult {
        guard bridge == nil else {
            return .failed
        }

        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce

        let bridge = AuthorizationControllerBridge(presentationAnchor: presentationAnchor)
        self.bridge = bridge
        defer { self.bridge = nil }

        switch await bridge.perform(requests: [request]) {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let authorizationCode = credential.authorizationCode,
                let code = String(data: authorizationCode, encoding: .utf8),
                !code.isEmpty
            else {
                return .failed
            }
            return .authorized(code: code)
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                return .cancelled
            }
            return .failed
        }
    }
}
