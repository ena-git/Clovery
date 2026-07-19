import AuthenticationServices
import UIKit

@MainActor
enum AuthenticationPresentationAnchor {
    static func current() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foregroundScenes = scenes.filter { $0.activationState == .foregroundActive }
        let windows = foregroundScenes.flatMap(\.windows) + scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}

@MainActor
final class AuthorizationControllerBridge: NSObject {
    private let presentationAnchor: @MainActor () -> ASPresentationAnchor
    private var continuation: CheckedContinuation<Result<ASAuthorization, Error>, Never>?

    init(presentationAnchor: @escaping @MainActor () -> ASPresentationAnchor) {
        self.presentationAnchor = presentationAnchor
    }

    func perform(
        requests: [ASAuthorizationRequest]
    ) async -> Result<ASAuthorization, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<ASAuthorization, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

extension AuthorizationControllerBridge: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        complete(with: .success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        complete(with: .failure(error))
    }
}

extension AuthorizationControllerBridge: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        presentationAnchor()
    }
}
