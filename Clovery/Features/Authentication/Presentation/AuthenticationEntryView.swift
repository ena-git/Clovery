import SwiftUI

struct AuthenticationEntryView: View {
    let showLogin: () -> Void
    let showSignUp: () -> Void

    var body: some View {
        GeometryReader { geometry in
            // Centered content
            VStack(spacing: 14) {
                Image(AuthenticationAsset.cloverHero.rawValue)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 108)

                Text("Clovery")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.authInk)

                Text("记录生活中的小确幸")
                    .cloveryFont(.caption)
                    .foregroundColor(.authInk.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            // Bottom CTA buttons pinned via overlay
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    Button(action: showSignUp) {
                        Text("注册")
                            .cloveryFont(.action)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.authAccent, in: Capsule())
                            .shadow(color: Color.authAccent.opacity(0.38), radius: 14, y: 5)
                    }
                    .buttonStyle(.plain)

                    Button(action: showLogin) {
                        Text("已有账户？登录")
                            .cloveryFont(.action)
                            .foregroundColor(.authAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(40, geometry.safeAreaInsets.bottom + 16))
            }
        }
        .background(Color.authBackground.ignoresSafeArea())
    }
}
