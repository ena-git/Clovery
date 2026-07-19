import SwiftUI

struct UpgradeNoticeView: View {
    let later: () -> Void
    let bindAccount: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Clovery 小更新")
                .cloveryFont(.action)
                .foregroundColor(.authInk)

            Text("你的日记仍然完整保留。你可以继续像以前一样使用，也可以绑定 Clovery 账户，为安全的跨设备同步做好准备。")
                .cloveryFont(.caption)
                .foregroundColor(.authInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Button("稍后", action: later)
                    .cloveryFont(.action)
                    .foregroundColor(.authInk)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.authBackground, in: Capsule())

                Button("绑定 Clovery 账户", action: bindAccount)
                    .cloveryFont(.caption)
                    .foregroundColor(.authBackground)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.authInk, in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .background(Color.authSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.authDashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
