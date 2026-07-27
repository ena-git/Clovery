import CryptoKit
import SwiftUI

struct AccountReconciliationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    let state: BootstrapReconciliationState
    let retry: () -> Void
    let logout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(AuthenticationAsset.cloverHero.rawValue)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180)
                    .accessibilityHidden(true)

                Text(title)
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    stageRow("正在确认账户", stage: .identity)
                    stageRow("正在安全保存日记与照片", stage: .migration)
                    stageRow("正在恢复已购权益", stage: .entitlement)
                    stageRow("正在同步云端内容", stage: .vault)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let message {
                    Text(message)
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }

                if case .working = state {
                    ProgressView()
                        .tint(.authInk)
                        .accessibilityLabel("正在整理数据")
                } else {
                    actionButtons
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(Color.authSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .stroke(
                        Color.authDashedBorder,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.authBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stageStates)
        .interactiveDismissDisabled()
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            Button("重试", action: retry)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Color.authInk, in: Capsule())
                .foregroundColor(.authBackground)

            HStack(spacing: 18) {
                Button("退出账户", action: logout)
                Button("联系支持") {
                    guard let url = supportURL else { return }
                    openURL(url)
                }
            }
            .foregroundColor(.authInk)
        }
        .cloveryFont(.caption)
        .buttonStyle(.plain)
    }

    private func stageRow(
        _ label: String,
        stage: ReconciliationStage
    ) -> some View {
        let stageState = stageStates[stage] ?? .pending
        return HStack(spacing: 12) {
            Group {
                switch stageState {
                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                case .active:
                    ProgressView()
                case .pending:
                    Image(systemName: "circle")
                }
            }
            .frame(width: 24, height: 24)
            .foregroundColor(.authInk)

            Text(label)
                .cloveryFont(.caption)
                .foregroundColor(stageState == .pending ? .authPlaceholder : .authInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(stageState.accessibilityText)")
    }

    private var title: String {
        switch state {
        case .working:
            "正在整理你的 Clovery"
        case .retryable:
            "暂时无法完成整理"
        case .needsAttention:
            "需要你的协助"
        }
    }

    private var message: String? {
        switch state {
        case .working:
            "完成前不会删除或覆盖原有日记、照片和购买记录。"
        case .retryable, .needsAttention:
            "支持编号：\(supportReference)"
        }
    }

    private var supportReference: String {
        BootstrapSupportReference.make(errorCode)
    }

    private var supportURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@clovery.cn"
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "Clovery 支持编号 \(supportReference)"
            )
        ]
        return components.url
    }

    private var errorCode: String {
        switch state {
        case .working:
            "bootstrap_working"
        case let .retryable(code), let .needsAttention(code):
            code
        }
    }

    private var stageStates: [ReconciliationStage: ReconciliationStageState] {
        guard case let .working(status) = state, let status else {
            return Dictionary(uniqueKeysWithValues: ReconciliationStage.allCases.map { ($0, .pending) })
        }
        let values: [(ReconciliationStage, AccountBootstrapStageState)] = [
            (.identity, status.stages.identity),
            (.migration, status.stages.migration),
            (.entitlement, status.stages.entitlement),
            (.vault, status.stages.vault)
        ]
        let active = values.first(where: { $0.1 != .complete })?.0
        return Dictionary(uniqueKeysWithValues: values.map { stage, value in
            if value == .complete { return (stage, .complete) }
            return (stage, stage == active ? .active : .pending)
        })
    }
}

enum BootstrapSupportReference {
    static func make(_ errorCode: String) -> String {
        SHA256.hash(data: Data(errorCode.utf8))
            .prefix(4)
            .map { String(format: "%02X", $0) }
            .joined()
    }
}

private enum ReconciliationStage: CaseIterable {
    case identity
    case migration
    case entitlement
    case vault
}

private enum ReconciliationStageState: Equatable {
    case complete
    case active
    case pending

    var accessibilityText: String {
        switch self {
        case .complete: "已完成"
        case .active: "进行中"
        case .pending: "等待中"
        }
    }
}
