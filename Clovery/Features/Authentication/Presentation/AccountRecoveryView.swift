import SwiftUI

struct AccountRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AccountRecoveryViewModel

    init(api: AccountRecoveryAPIProtocol) {
        _viewModel = StateObject(wrappedValue: AccountRecoveryViewModel(api: api))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 28)

                    if viewModel.didComplete {
                        completionCard
                    } else {
                        recoveryForm
                    }

                    Spacer(minLength: 30)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .dynamicTypeSize(.xSmall ... .large)
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
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("找回账户")
                .cloveryFont(.heading)
                .foregroundColor(.authInk)
            Text("重置你的密码")
                .cloveryFont(.caption)
                .foregroundColor(.authInk.opacity(0.7))
        }
        .multilineTextAlignment(.center)
    }

    private var recoveryForm: some View {
        VStack(spacing: 0) {
            AuthDashedCard(height: 214) {
                VStack(spacing: 14) {
                    AuthTextField(
                        placeholder: "Clovery ID...",
                        text: $viewModel.loginID,
                        contentType: .username
                    )
                    AuthTextField(
                        placeholder: "新密码…",
                        text: $viewModel.newPassword,
                        isSecure: true,
                        contentType: .newPassword
                    )
                    AuthTextField(
                        placeholder: "确认密码…",
                        text: $viewModel.confirmPassword,
                        isSecure: true,
                        contentType: .newPassword,
                        submitLabel: .go,
                        onSubmit: submit
                    )
                }
                .padding(.vertical, 14)
            }
            .frame(maxWidth: 347)
            .padding(.top, 22)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .cloveryFont(.caption)
                    .foregroundColor(.authError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }

            Button(action: submit) {
                Group {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.authInk)
                    } else {
                        Text("重置密码")
                            .cloveryFont(.action)
                    }
                }
                .foregroundColor(.authInk)
                .frame(minWidth: 140, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
            .padding(.top, 10)
        }
    }

    private var completionCard: some View {
        AuthDashedCard(height: 200) {
            VStack(spacing: 16) {
                Text("密码已更新")
                    .cloveryFont(.body)
                    .foregroundColor(.authInk)
                Text("之前的登录会话已退出，请使用新密码重新登录。")
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("返回登录", action: { dismiss() })
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 347)
        .padding(.top, 36)
    }

    private func submit() {
        Task {
            await viewModel.submit()
        }
    }
}
