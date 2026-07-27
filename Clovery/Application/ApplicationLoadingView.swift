import SwiftUI

struct ApplicationLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(AuthenticationAsset.cloverHero.rawValue)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
            Text("Clovery")
                .cloveryFont(.title)
                .foregroundColor(.authInk)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.authBackground.ignoresSafeArea())
    }
}

struct BootstrapHoldingView: View {
    let state: BootstrapReconciliationState
    let retry: () -> Void
    let logout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(AuthenticationAsset.cloverHero.rawValue)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)

                Text(title)
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)

                if let detail {
                    Text(detail)
                        .cloveryFont(.caption)
                        .foregroundColor(.authPlaceholder)
                        .multilineTextAlignment(.center)
                }

                if case .working = state {
                    ProgressView().tint(.authInk)
                } else {
                    HStack(spacing: 18) {
                        Button("重试", action: retry)
                        Button("退出账户", action: logout)
                    }
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk)
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
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
            .padding(.vertical, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.authBackground.ignoresSafeArea())
    }

    private var title: String {
        switch state {
        case .working:
            return "正在整理你的 Clovery"
        case .retryable:
            return "暂时无法完成整理"
        case .needsAttention:
            return "需要你的协助"
        }
    }

    private var detail: String? {
        switch state {
        case .working:
            return "正在安全确认账户、日记、照片与已购权益"
        case let .retryable(code):
            return "请检查网络后重试 · \(code)"
        case let .needsAttention(code):
            return "请保留此支持编号：\(code)"
        }
    }
}
