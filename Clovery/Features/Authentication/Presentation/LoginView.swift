import SwiftUI

private struct LoginFormStartKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LoginViewModel
    let showSignUp: () -> Void
    var recoverAccount: () -> Void = {}
    var authenticateWithProvider: (AuthenticationProviderKind) -> Void = { _ in }
    var quickProviders: [AuthenticationProviderKind] = []
    var providerMessage: String?

    @State private var panelY: CGFloat = 0

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController,
        showSignUp: @escaping () -> Void,
        recoverAccount: @escaping () -> Void = {},
        authenticateWithProvider: @escaping (AuthenticationProviderKind) -> Void = { _ in },
        quickProviders: [AuthenticationProviderKind] = [],
        providerMessage: String? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: LoginViewModel(api: api, sessionController: sessionController)
        )
        self.showSignUp = showSignUp
        self.recoverAccount = recoverAccount
        self.authenticateWithProvider = authenticateWithProvider
        self.quickProviders = quickProviders
        self.providerMessage = providerMessage
    }

    private var canSubmit: Bool {
        !viewModel.loginID.isEmpty && !viewModel.password.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header – cream background, measures its bottom edge
                    VStack(spacing: 0) {
                        Text("LOG IN")
                            .cloveryFont(.title)
                            .foregroundColor(.authInk)
                            .tracking(4)
                        Text("Welcome back to us!")
                            .cloveryFont(.caption)
                            .foregroundColor(.authInk)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: LoginFormStartKey.self,
                            value: g.frame(in: .global).maxY
                        )
                    })

                    // Input fields – stacked pill corners (top: square top-right, bottom: square bottom-right)
                    VStack(spacing: 0) {
                        AuthTextField(
                            placeholder: "Clovery ID...",
                            text: $viewModel.loginID,
                            contentType: .username,
                            cornerRadii: .init(topLeading: 60, bottomLeading: 60, bottomTrailing: 60, topTrailing: 0)
                        )
                        AuthTextField(
                            placeholder: "Password...",
                            text: $viewModel.password,
                            isSecure: true,
                            contentType: .password,
                            submitLabel: .go,
                            onSubmit: submit,
                            cornerRadii: .init(topLeading: 60, bottomLeading: 60, bottomTrailing: 0, topTrailing: 60)
                        )
                    }

                    errorMessage
                        .padding(.top, 10)

                    Spacer(minLength: 36)

                    // Submit button
                    Button(action: submit) {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView().tint(.authInk)
                            } else {
                                Text("LOG IN")
                                    .cloveryFont(.action)
                                    .tracking(2)
                            }
                        }
                        .foregroundColor(canSubmit ? .authInk : .authPlaceholder)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)
                    .animation(.easeInOut(duration: 0.2), value: canSubmit)

                    if !quickProviders.isEmpty {
                        AuthDivider()
                            .padding(.top, 24)
                        providerRow
                            .padding(.top, 20)
                    }

                    Spacer(minLength: 32)

                    HStack(spacing: 4) {
                        Text("New here?")
                            .foregroundColor(.authPlaceholder)
                        Button(action: showSignUp) {
                            Text("Sign Up")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.authInk)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .cloveryFont(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, max(36, geometry.safeAreaInsets.bottom + 16))
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .dynamicTypeSize(.xSmall ... .large)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            // Panel positioned at measured form-start y
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
        .onPreferenceChange(LoginFormStartKey.self) { value in
            if value > 0 { panelY = value }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                AuthBackButton(action: { dismiss() })
            }
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let msg = viewModel.errorMessage ?? providerMessage {
            Text(msg)
                .cloveryFont(.caption)
                .foregroundColor(.authError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .accessibilityLabel(msg)
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
