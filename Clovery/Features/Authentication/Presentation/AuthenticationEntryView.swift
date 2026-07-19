import SwiftUI

struct AuthenticationEntryView: View {
    let showLogin: () -> Void
    let showSignUp: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: max(110, geometry.size.height * 0.18))

                    Image(AuthenticationAsset.cloverHero.rawValue)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 237, height: 237)
                        .zIndex(1)

                    AuthDashedCard(height: 251) {
                        VStack(spacing: 26) {
                            entryButton(title: "LOG IN", action: showLogin)
                            entryButton(title: "SIGN UP", action: showSignUp)
                        }
                    }
                    .frame(maxWidth: 340)
                    .offset(y: -24)

                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color.authBackground.ignoresSafeArea())
    }

    private func entryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.authAction)
                .foregroundColor(.authInk)
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(Color.authSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "LOG IN" ? "登录" : "注册")
    }
}
