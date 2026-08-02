import SwiftUI

extension AuthenticationProviderKind {
    var asset: AuthenticationAsset {
        switch self {
        case .apple:
            return .apple
        case .google:
            return .google
        case .huawei:
            return .huawei
        case .passkey:
            return .clovery
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .apple:
            return "使用 Apple 登录"
        case .google:
            return "使用 Google 登录"
        case .huawei:
            return "使用华为账号登录"
        case .passkey:
            return "使用 Clovery 通行密钥登录"
        }
    }
}

struct AuthProviderButton: View {
    let provider: AuthenticationProviderKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(provider.asset.rawValue)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .frame(width: 49, height: 49)
                .background(Color.authSurface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.accessibilityLabel)
    }
}
