import SwiftUI

struct DeleteAccountConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let cloveryID: String
    @ObservedObject var viewModel: AccountSecurityViewModel
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 42))
                        .foregroundColor(.red)
                        .accessibilityHidden(true)

                    Text("确认删除 Clovery 账户")
                        .cloveryFont(.action)
                        .foregroundColor(.authInk)
                        .multilineTextAlignment(.center)

                    Text("提交后，你的 Clovery 账户、Vault、日记与照片、服务端权益将进入计划删除流程。当前设备会立即退出，完成删除后无法恢复。")
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("请输入 Clovery ID：\(cloveryID)")
                            .cloveryFont(.caption)
                            .foregroundColor(.authInk)
                        TextField("完整输入 Clovery ID", text: $confirmation)
                            .accessibilityIdentifier("account-deletion-confirmation-field")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 52)
                            .background(Color.white, in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.authDashedBorder, lineWidth: 1.5)
                            }
                            .cloveryFont(.caption)
                    }

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .cloveryFont(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            await viewModel.requestDeletion(confirmation: confirmation)
                        }
                    } label: {
                        Group {
                            if viewModel.isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("确认并提交删除请求")
                                    .cloveryFont(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .accessibilityIdentifier("account-deletion-confirm-button")
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .background(Color.red, in: Capsule())
                    .disabled(
                        viewModel.isDeleting || !viewModel.canConfirmDeletion(confirmation)
                    )
                    .opacity(
                        viewModel.canConfirmDeletion(confirmation) && !viewModel.isDeleting
                            ? 1
                            : 0.4
                    )
                }
                .padding(24)
            }
            .background(Color.authBackground.ignoresSafeArea())
            .navigationTitle("第二次确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .cloveryFont(.caption)
                        .foregroundColor(.authInk)
                }
            }
        }
        .accessibilityIdentifier("account-deletion-screen")
        .interactiveDismissDisabled(viewModel.isDeleting)
    }
}
