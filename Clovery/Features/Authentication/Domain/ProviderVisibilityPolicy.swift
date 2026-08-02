enum ClientPlatform: CaseIterable {
    case iOS
    case huaweiHarmony
    case androidOther
}

enum PrimaryAuthenticationMethod: Equatable {
    case cloveryID
}

enum AuthenticationProviderKind: Hashable {
    case apple
    case google
    case huawei
    case passkey
}

struct ProviderVisibilityPolicy {
    func defaultMethod(for platform: ClientPlatform) -> PrimaryAuthenticationMethod {
        .cloveryID
    }

    func quickProviders(for platform: ClientPlatform) -> [AuthenticationProviderKind] {
        switch platform {
        case .iOS:
            return [.apple, .google]
        case .huaweiHarmony:
            return [.huawei]
        case .androidOther:
            return [.google]
        }
    }
}
