import SwiftUI

private struct SignUpFormStartKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SignUpViewModel
    let showLogin: () -> Void
    var authenticateWithProvider: (AuthenticationProviderKind) -> Void = { _ in }
    var quickProviders: [AuthenticationProviderKind] = []
    var providerMessage: String?

    @State private var panelY: CGFloat = 0

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController,
        showLogin: @escaping () -> Void,
        authenticateWithProvider: @escaping (AuthenticationProviderKind) -> Void = { _ in },
        quickProviders: [AuthenticationProviderKind] = [],
        providerMessage: String? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: SignUpViewModel(api: api, sessionController: sessionController)
        )
        self.showLogin = showLogin
        self.authenticateWithProvider = authenticateWithProvider
        self.quickProviders = quickProviders
        self.providerMessage = providerMessage
    }

    private var canSubmit: Bool {
        !viewModel.loginID.isEmpty
            && !viewModel.password.isEmpty
            && !viewModel.confirmPassword.isEmpty
            && viewModel.hasAcceptedLegalTerms
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header – cream background, measures its bottom edge
                    VStack(spacing: 0) {
                        Text("SIGN UP")
                            .cloveryFont(.title)
                            .foregroundColor(.authInk)
                            .tracking(4)
                        Text("Welcome to join us!")
                            .cloveryFont(.caption)
                            .foregroundColor(.authInk)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: SignUpFormStartKey.self,
                            value: g.frame(in: .global).maxY
                        )
                    })

                    // Input fields – stacked pill corners
                    VStack(spacing: 0) {
                        AuthTextField(
                            placeholder: "Clovery ID...",
                            text: $viewModel.loginID,
                            contentType: .username,
                            cornerRadii: .init(topLeading: 0, bottomLeading: 60, bottomTrailing: 60, topTrailing: 60)
                        )
                        AuthTextField(
                            placeholder: "Password...",
                            text: $viewModel.password,
                            isSecure: true,
                            contentType: .newPassword,
                            cornerRadii: .init(topLeading: 60, bottomLeading: 0, bottomTrailing: 60, topTrailing: 60)
                        )
                        AuthTextField(
                            placeholder: "Confirm Password...",
                            text: $viewModel.confirmPassword,
                            isSecure: true,
                            contentType: .newPassword,
                            submitLabel: .join,
                            onSubmit: submit,
                            cornerRadii: .init(topLeading: 60, bottomLeading: 0, bottomTrailing: 60, topTrailing: 60)
                        )
                    }

                    requirementsSection
                        .padding(.top, 10)

                    formMessage
                        .padding(.top, 8)

                    LegalAcknowledgementView(isAccepted: $viewModel.hasAcceptedLegalTerms)
                        .padding(.top, 16)

                    Spacer(minLength: 28)

                    // Submit button
                    Button(action: submit) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView().tint(.authInk)
                            } else {
                                Text("SIGN UP")
                                    .cloveryFont(.action)
                                    .tracking(2)
                            }
                        }
                        .foregroundColor(canSubmit ? .authInk : .authPlaceholder)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting || !canSubmit)
                    .animation(.easeInOut(duration: 0.2), value: canSubmit)

                    if !quickProviders.isEmpty {
                        AuthDivider()
                            .padding(.top, 24)
                        providerRow
                            .padding(.top, 20)
                    }

                    Spacer(minLength: 32)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(.authPlaceholder)
                        Button(action: showLogin) {
                            Text("Log In")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.authInk)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .cloveryFont(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, max(56, geometry.safeAreaInsets.bottom + 32))
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .dynamicTypeSize(.xSmall ... .large)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            GeometryReader { geo in
                Color.authPanel
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 0, bottomLeading: 0,
                                bottomTrailing: 0, topTrailing: 60
                            ),
                            style: .continuous
                        )
                    )
                    .frame(width: geo.size.width - 56)
                    .frame(height: max(0, geo.size.height + geo.safeAreaInsets.bottom - panelY))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: panelY)
                Color.authBackground
                    .frame(height: panelY)
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()
        }
        .onPreferenceChange(SignUpFormStartKey.self) { value in
            if value > 0 { panelY = value }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                AuthBackButton(action: { dismiss() })
            }
        }
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirementRow(
                "ID 以字母开头，4-24 位小写字母 / 数字 / 下划线",
                met: viewModel.loginID.isEmpty ? nil
                    : AuthenticationValidation.isValidCloveryID(
                        AuthenticationValidation.normalizedCloveryID(viewModel.loginID)
                    )
            )
            requirementRow(
                "密码至少 8 位",
                met: viewModel.password.isEmpty ? nil
                    : AuthenticationValidation.isValidPassword(viewModel.password)
            )
            if !viewModel.confirmPassword.isEmpty {
                requirementRow(
                    "两次密码一致",
                    met: viewModel.password == viewModel.confirmPassword
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private func requirementRow(_ text: String, met: Bool?) -> some View {
        let color: Color = met == true ? .requirementMet : .authPlaceholder
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: met == true ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .cloveryFont(.footnote)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var formMessage: some View {
        if let message = validationMessage ?? viewModel.errorMessage ?? providerMessage {
            Text(message)
                .cloveryFont(.caption)
                .foregroundColor(.authError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .accessibilityLabel(message)
        }
    }

    private var validationMessage: String? {
        switch viewModel.validationError {
        case .invalidCloveryID: return "Clovery ID 格式不符合要求"
        case .invalidPassword: return "密码至少需要 8 位"
        case .passwordsDoNotMatch: return "两次输入的密码不一致"
        case .legalTermsNotAccepted: return "请先阅读并同意用户协议和隐私政策"
        case nil: return nil
        }
    }

    private var providerRow: some View {
        HStack(spacing: 12) {
            ForEach(quickProviders, id: \.self) { provider in
                AuthProviderButton(
                    provider: provider,
                    action: { authenticateWithProvider(provider) }
                )
            }
        }
    }

    private func submit() {
        Task { await viewModel.submit() }
    }
}
