import Combine
import Foundation

@MainActor
final class AuthenticationProviderViewModel: ObservableObject {
    @Published private(set) var message: String?
    @Published private(set) var isAuthenticating = false

    private let federatedCoordinator: FederatedLoginCoordinator
    private let passkeyCoordinator: PasskeyLoginCoordinator
    private let appleProvider: AppleAuthenticationProvider
    private let googleProvider: WebAuthenticationProvider
    private let huaweiProvider: WebAuthenticationProvider
    private let passkeyProvider: PasskeyAuthenticationProvider

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController
    ) {
        federatedCoordinator = FederatedLoginCoordinator(
            api: api,
            deviceRegistration: { try sessionController.deviceRegistration() },
            acceptSession: { try sessionController.accept($0) }
        )
        passkeyCoordinator = PasskeyLoginCoordinator(
            api: api,
            deviceRegistration: { try sessionController.deviceRegistration() },
            acceptSession: { try sessionController.accept($0) }
        )
        appleProvider = AppleAuthenticationProvider()
        googleProvider = WebAuthenticationProvider(
            configuration: WebAuthenticationConfiguration.current(provider: .google)
        )
        huaweiProvider = WebAuthenticationProvider(
            configuration: WebAuthenticationConfiguration.current(provider: .huawei)
        )
        passkeyProvider = PasskeyAuthenticationProvider()
    }

    func isAvailable(_ provider: AuthenticationProviderKind) -> Bool {
        switch provider {
        case .apple:
            return appleProvider.isAvailable
        case .google:
            return googleProvider.isAvailable
        case .huawei:
            return huaweiProvider.isAvailable
        case .passkey:
            return passkeyProvider.isAvailable
        }
    }

    func authenticate(_ provider: AuthenticationProviderKind) async {
        guard !isAuthenticating else {
            return
        }
        message = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch provider {
        case .apple:
            await present(
                await federatedCoordinator.authenticate(
                    provider: .apple,
                    using: appleProvider
                )
            )
        case .google:
            await present(
                await federatedCoordinator.authenticate(
                    provider: .google,
                    using: googleProvider
                )
            )
        case .huawei:
            await present(
                await federatedCoordinator.authenticate(
                    provider: .huawei,
                    using: huaweiProvider
                )
            )
        case .passkey:
            await present(
                await passkeyCoordinator.authenticate(using: passkeyProvider)
            )
        }
    }

    private func present(_ outcome: FederatedLoginOutcome) async {
        switch outcome {
        case .authenticated, .cancelled:
            message = nil
        case .unavailable:
            message = "该登录方式暂未配置，请稍后再试"
        case .requiresExistingAccountBinding:
            message = "该登录方式尚未绑定 Clovery 账户，请先登录已有账户后绑定"
        case .failed:
            message = "快捷登录失败，请稍后再试"
        }
    }

    private func present(_ outcome: PasskeyLoginOutcome) async {
        switch outcome {
        case .authenticated, .cancelled:
            message = nil
        case .unavailable:
            message = "此设备暂不支持 Clovery 通行密钥"
        case .failed:
            message = "通行密钥登录失败，请稍后再试"
        }
    }
}
