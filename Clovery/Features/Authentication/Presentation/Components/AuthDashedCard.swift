import SwiftUI

struct AuthDashedCard<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 25)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 60, style: .continuous)
                    .stroke(
                        Color.authDashedBorder,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 60, style: .continuous))
    }
}
