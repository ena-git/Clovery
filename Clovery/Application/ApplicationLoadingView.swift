import SwiftUI

struct ApplicationLoadingView: View {
    var showsTitle = true

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(AuthenticationAsset.cloverHero.rawValue)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
            if showsTitle {
                Text("Clovery")
                    .cloveryFont(.title)
                    .foregroundColor(.authInk)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.authBackground.ignoresSafeArea())
    }
}
