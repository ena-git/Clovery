import SwiftUI

struct UpgradeNoticeView: View {
    let acknowledge: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 24)
                    noticeCard
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .interactiveDismissDisabled()
    }

    private var noticeCard: some View {
        VStack(spacing: 0) {
            Image("UpgradeClover")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .padding(.bottom, 14)

            Text("欢迎升级 Clovery")
                .cloveryFont(.body)
                .foregroundColor(.authInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Text("为了安全地保存并同步你的日记、照片和已购权益，本次更新需要创建或登录 Clovery 账户。你的现有内容仍保留在设备中，完成绑定前不会删除或覆盖。")
                .cloveryFont(.caption)
                .foregroundColor(.authInk.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.bottom, 28)

            Button("我已知晓", action: acknowledge)
                .cloveryFont(.caption)
                .foregroundColor(.authBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.authInk, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
        .padding(.bottom, 28)
        .background(
            Color.authSurface,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    Color.authDashedBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
        }
        .padding(.horizontal, 18)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
