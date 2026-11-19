import SwiftUI
import UIKit

struct AuthBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HandDrawnBackArrow()
                .stroke(
                    Color.authInk,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 26, height: 20)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(AuthBackButtonStyle())
        .accessibilityLabel("返回")
    }
}

private struct HandDrawnBackArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height

        // shaft — gentle upward bow
        p.move(to: CGPoint(x: w, y: h * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.52),
            control: CGPoint(x: w * 0.5, y: h * 0.44)
        )
        // arrowhead top leg
        p.move(to: CGPoint(x: 0, y: h * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.40, y: 0),
            control: CGPoint(x: w * 0.10, y: h * 0.20)
        )
        // arrowhead bottom leg
        p.move(to: CGPoint(x: 0, y: h * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.40, y: h),
            control: CGPoint(x: w * 0.10, y: h * 0.82)
        )
        return p
    }
}

private struct AuthBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.60), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.prepare()
                    g.impactOccurred()
                }
            }
    }
}
