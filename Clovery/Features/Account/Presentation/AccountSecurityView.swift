import SwiftUI

struct AccountSecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AccountSecurityViewModel
    @State private var showsDeletionConfirmation = false
    @State private var presentedDocument: LegalDocument?

    private let highlightGreen = Color(red: 122 / 255.0, green: 179 / 255.0, blue: 117 / 255.0)
    private let borderColor = Color(red: 0xd6 / 255.0, green: 0xd6 / 255.0, blue: 0xd6 / 255.0)

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
            ZStack {
                Color.authBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Navigation row
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "arrow.backward")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.authInk)
                                    .padding(12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.horizontal, 8)

                        // Large centered title
                        Text("账户与安全")
                            .cloveryFont(.heading)
                            .foregroundColor(.authInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                            .padding(.bottom, 16)

                        // Arch + content card
                        ZStack(alignment: .top) {
                            // Decorative ring arch (drawn first = behind card)
                            Circle()
                                .stroke(highlightGreen, lineWidth: 16)
                                .frame(width: 200, height: 200)
                                .frame(maxWidth: .infinity)

                            // Content card (drawn second = in front, hides arch bottom)
                            VStack(spacing: 14) {
                                accountSection

                                VStack(alignment: .leading, spacing: 8) {
                                    sectionLabel("法律与隐私")
                                    legalSection
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    sectionLabel("账户管理")
                                    deletionSection
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.authPanel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.top, 88) // exposes top 88pt of arch above card
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSafariView(document: document)
                .ignoresSafeArea()
        }
        .onChange(of: viewModel.didAcceptDeletion) { accepted in
            if accepted { dismiss() }
        }
    }

    // MARK: - Account section

    @ViewBuilder
    private var accountSection: some View {
        sectionCard {
            if viewModel.isLoading && viewModel.summary == nil {
                HStack {
                    ProgressView().tint(.authPlaceholder)
                    Text("正在加载账户…")
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if let summary = viewModel.summary {
                infoRow(label: "Clovery ID", value: summary.cloveryID)
                rowDivider()
                infoRow(
                    label: "登录方式",
                    value: viewModel.providerNames.isEmpty
                        ? "Clovery 密码"
                        : viewModel.providerNames.joined(separator: "、")
                )
                rowDivider()
                infoRow(label: "安全凭证", value: credentialDescription(summary))
            } else {
                VStack(spacing: 4) {
                    Text(viewModel.errorMessage ?? "账户信息加载失败，请检查网络后重试")
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Text("重试")
                            .cloveryFont(.caption)
                            .foregroundColor(.authAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Legal section

    private var legalSection: some View {
        sectionCard {
            actionRow(label: "用户协议") { presentedDocument = .terms }
            rowDivider()
            actionRow(label: "隐私政策") { presentedDocument = .privacy }
        }
    }

    // MARK: - Deletion section

    private var deletionSection: some View {
        sectionCard {
            Button {
                showsDeletionConfirmation = true
            } label: {
                HStack {
                    Text("删除账户")
                        .cloveryFont(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color.red.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account-deletion-entry")
            .disabled(viewModel.cloveryID == nil)
        }
    }

    // MARK: - Reusable primitives

    private func sectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .cloveryFont(.footnote)
            .foregroundColor(.authInk)
            .padding(.leading, 4)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .cloveryFont(.caption)
                .foregroundColor(.authPlaceholder)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .cloveryFont(.caption)
                .foregroundColor(.authInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func actionRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(borderColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private func rowDivider() -> some View {
        Divider()
            .overlay(borderColor)
            .padding(.vertical, 2)
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
