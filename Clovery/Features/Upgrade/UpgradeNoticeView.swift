import SwiftUI

struct UpgradeNoticeView: View {
    let later: () -> Void
    let bindAccount: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("A little update for Clovery")
                .font(.authAction)
                .foregroundColor(.authInk)

            Text("Your diary is still here. You can keep using it as before, or bind a Clovery account to prepare for secure cross-device sync.")
                .font(.authCaption)
                .foregroundColor(.authInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Button("LATER", action: later)
                    .font(.authAction)
                    .foregroundColor(.authInk)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.authBackground, in: Capsule())

                Button("BIND CLOVERY ACCOUNT", action: bindAccount)
                    .font(.authCaption)
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
