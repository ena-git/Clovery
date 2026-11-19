import SwiftUI
import UIKit

struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    let g = UIImpactFeedbackGenerator(style: .medium)
                    g.prepare()
                    g.impactOccurred()
                }
            }
    }
}
