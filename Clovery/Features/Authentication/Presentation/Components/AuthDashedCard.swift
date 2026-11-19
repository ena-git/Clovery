import SwiftUI

struct DiaryWaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY + 1.5))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.midY - 1.5),
            control1: CGPoint(x: rect.width * 0.28, y: rect.midY - 4),
            control2: CGPoint(x: rect.width * 0.72, y: rect.midY + 4)
        )
        return path
    }
}

struct AuthDashedCard<Content: View>: View {
    let height: CGFloat
    var cornerRadius: CGFloat = 60
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 25)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.authDashedBorder,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
