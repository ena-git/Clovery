import SwiftUI

struct IdentityClaimRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: IdentityClaimRegistrationViewModel
    private let provider: IdentityProvider
    private let reauthorize: (IdentityProvider) -> Void

    init(
        api: IdentityClaimAPIProtocol,
        sessionHandler: IdentityClaimRegistrationSessionHandling,
        claim: IdentityClaimContext,
        sourceKind: BootstrapSourceKind,
        reauthorize: @escaping (IdentityProvider) -> Void
    ) {
        provider = claim.provider
        self.reauthorize = reauthorize
        _viewModel = StateObject(
            wrappedValue: IdentityClaimRegistrationViewModel(
                api: api,
                sessionHandler: sessionHandler,
                claim: claim,
                sourceKind: sourceKind
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 35)

                    AuthDivider()
                        .padding(.top, 20)

                    AuthDashedCard(height: 360) {
                        VStack(spacing: 26) {
                            AuthTextField(
                                placeholder: "Clovery ID...",
                                text: $viewModel.loginID,
                                contentType: .username
                            )
                            AuthTextField(
                                placeholder: "密码…",
                                text: $viewModel.password,
                                isSecure: true,
                                contentType: .newPassword
                            )
                            AuthTextField(
                                placeholder: "确认密码…",
                                text: $viewModel.confirmPassword,
                                isSecure: true,
                                contentType: .newPassword,
                                submitLabel: .join,
                                onSubmit: submit
                            )
                        }
                    }
                    .frame(maxWidth: 347)
                    .padding(.top, 24)

                    formMessage
                        .padding(.top, 8)

                    Button(action: submit) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView().tint(.authInk)
                            } else {
                                Text("创建并继续").cloveryFont(.action)
                            }
                        }
                        .foregroundColor(.authInk)
                        .frame(minWidth: 160, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting || !viewModel.hasAcceptedLegalTerms)
                    .padding(.top, 10)

                    LegalAcknowledgementView(
                        isAccepted: $viewModel.hasAcceptedLegalTerms
                    )
                    .frame(maxWidth: 310, alignment: .leading)
                    .padding(.top, 4)

                    Text("完成后，\(provider.displayName) 将成为此 Clovery 账户的一种登录方式")
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 10)

                    Spacer(minLength: 30)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.authBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(AuthenticationAsset.backArrow.rawValue)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 22)
                }
                .accessibilityLabel("返回")
            }
        }
        .onChange(of: viewModel.reauthorizationRequest) { request in
            guard let request = viewModel.consumeReauthorizationRequest() else {
                return
            }
            reauthorize(request)
        }
        .onDisappear {
            viewModel.clearSensitiveState()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("创建 Clovery 账户")
                .cloveryFont(.title)
                .foregroundColor(.authInk)
            Text("已验证 \(provider.displayName) 登录，请设置你的 Clovery ID")
                .cloveryFont(.caption)
                .foregroundColor(.authInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var formMessage: some View {
        if let message = validationMessage ?? viewModel.errorMessage {
            Text(message)
                .cloveryFont(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel(message)
        }
    }

    private var validationMessage: String? {
        switch viewModel.validationError {
        case .invalidCloveryID:
            return "Clovery ID 需以字母开头，使用 4–24 位小写字母、数字或下划线"
        case .invalidPassword:
            return "密码至少需要 8 位"
        case .passwordsDoNotMatch:
            return "两次输入的密码不一致"
        case .legalTermsNotAccepted:
            return "请先阅读并同意用户协议和隐私政策"
        case nil:
            return nil
        }
    }

    private func submit() {
        Task { await viewModel.submit() }
    }
}

private extension IdentityProvider {
    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        case .huawei:
            return "华为账号"
        }
    }
}
