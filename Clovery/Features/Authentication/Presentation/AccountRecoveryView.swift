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
                        .padding(.top, 32)

                    if viewModel.didComplete {
                        completionCard
                    } else {
                        recoveryForm
                    }

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
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text("找回账户")
                .cloveryFont(.title)
                .foregroundColor(.authInk)
            Text("使用 Clovery 恢复码")
                .cloveryFont(.action)
                .foregroundColor(.authInk)
        }
        .multilineTextAlignment(.center)
    }

    private var recoveryForm: some View {
        VStack(spacing: 0) {
            AuthDashedCard(height: 408) {
                VStack(spacing: 20) {
                    AuthTextField(
                        placeholder: "Clovery ID...",
                        text: $viewModel.loginID,
                        contentType: .username
                    )
                    AuthTextField(
                        placeholder: "恢复码…",
                        text: $viewModel.recoveryCode,
                        contentType: .oneTimeCode
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
            }
            .frame(maxWidth: 347)
            .padding(.top, 26)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .cloveryFont(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
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
                .frame(minWidth: 190, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
            .padding(.top, 14)
        }
    }

    private var completionCard: some View {
        AuthDashedCard(height: 230) {
            VStack(spacing: 22) {
                Text("密码已更新")
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                Text("之前的登录会话已退出，请使用新密码重新登录。")
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("返回登录", action: { dismiss() })
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 347)
        .padding(.top, 42)
    }

    private func submit() {
        Task {
            await viewModel.submit()
        }
    }
}
