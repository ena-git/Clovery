import SwiftUI

struct AccountSecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AccountSecurityViewModel
    @State private var showsDeletionConfirmation = false

    init(
        api: AccountManagementAPIProtocol,
        session: AccountDeletionSessionEnding,
        entitlementCache: AccountEntitlementCacheClearing,
        entitlementState: AccountEntitlementStateResetting
    ) {
        _viewModel = StateObject(
            wrappedValue: AccountSecurityViewModel(
                api: api,
                session: session,
                entitlementCache: entitlementCache,
                entitlementState: entitlementState
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    accountCard
                    legalCard
                    deletionCard
                }
                .padding(20)
            }
            .background(Color.authBackground.ignoresSafeArea())
            .navigationTitle("账户与安全")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .cloveryFont(.caption)
                        .foregroundColor(.authInk)
                }
            }
        }
        .accessibilityIdentifier("account-security-screen")
        .task { await viewModel.load() }
        .sheet(isPresented: $showsDeletionConfirmation) {
            if let cloveryID = viewModel.cloveryID {
                DeleteAccountConfirmationView(
                    cloveryID: cloveryID,
                    viewModel: viewModel
                )
            }
        }
        .onChange(of: viewModel.didAcceptDeletion) { accepted in
            if accepted { dismiss() }
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        if viewModel.isLoading && viewModel.summary == nil {
            card {
                ProgressView("正在加载账户…")
                    .cloveryFont(.caption)
                    .tint(.authInk)
            }
        } else if let summary = viewModel.summary {
            card {
                VStack(alignment: .leading, spacing: 18) {
                    detailRow(title: "Clovery ID", value: summary.cloveryID)
                    detailRow(
                        title: "已绑定登录方式",
                        value: viewModel.providerNames.isEmpty
                            ? "Clovery 密码"
                            : viewModel.providerNames.joined(separator: "、")
                    )
                    detailRow(
                        title: "安全凭证",
                        value: credentialDescription(summary)
                    )
                }
            }
        } else {
            card {
                VStack(spacing: 14) {
                    Text(viewModel.errorMessage ?? "暂时无法读取账户信息")
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await viewModel.load() }
                    }
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk)
                    .frame(minWidth: 100, minHeight: 44)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var legalCard: some View {
        card {
            VStack(spacing: 8) {
                Text("法律与隐私")
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                LegalDocumentLinksView()
                    .cloveryFont(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var deletionCard: some View {
        card {
            VStack(spacing: 12) {
                Text("删除账户")
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                Text("删除请求提交后会立即退出当前设备，服务端将按隐私政策进入计划删除流程。")
                    .cloveryFont(.caption)
                    .foregroundColor(.authPlaceholder)
                    .multilineTextAlignment(.center)
                Button("继续删除账户") {
                    showsDeletionConfirmation = true
                }
                .accessibilityIdentifier("account-deletion-entry")
                .cloveryFont(.caption)
                .foregroundColor(.red)
                .frame(minWidth: 160, minHeight: 44)
                .disabled(viewModel.cloveryID == nil)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func card<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Color.authSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        Color.authDashedBorder,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .cloveryFont(.caption)
                .foregroundColor(.authPlaceholder)
            Text(value)
                .cloveryFont(.body)
                .foregroundColor(.authInk)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func credentialDescription(_ summary: AccountSummary) -> String {
        var parts: [String] = []
        if summary.hasPassword { parts.append("密码") }
        if summary.passkeyCount > 0 { parts.append("通行密钥 \(summary.passkeyCount)") }
        if summary.recoveryCodesRemaining > 0 {
            parts.append("恢复码 \(summary.recoveryCodesRemaining)")
        }
        return parts.isEmpty ? "建议补充恢复方式" : parts.joined(separator: "、")
    }
}
