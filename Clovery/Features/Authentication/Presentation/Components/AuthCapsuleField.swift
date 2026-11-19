import SwiftUI
import UIKit

struct AuthCapsuleField<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .background(Color.authSurface, in: Capsule())
    }
}

struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}
    var cornerRadii: RectangleCornerRadii? = nil

    @FocusState private var isFocused: Bool
    @State private var showPassword = false

    private var effectiveRadii: RectangleCornerRadii {
        cornerRadii ?? .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 14, topTrailing: 14)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isSecure && !showPassword {
                    SecureField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundColor(.authPlaceholder)
                    )
                } else {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundColor(.authPlaceholder)
                    )
                }
            }
            .cloveryFont(.caption)
            .foregroundColor(.authInk)
            .focused($isFocused)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)

            if isSecure {
                Button {
                    showPassword.toggle()
                } label: {
                    Text(showPassword ? "隐藏" : "显示")
                        .cloveryFont(.footnote)
                        .foregroundColor(.authPlaceholder)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, cornerRadii != nil ? 24 : 17)
        .frame(maxWidth: .infinity)
        .background(
            Color.authSurface,
            in: UnevenRoundedRectangle(cornerRadii: effectiveRadii, style: .continuous)
        )
        .overlay {
            UnevenRoundedRectangle(cornerRadii: effectiveRadii, style: .continuous)
                .stroke(
                    isFocused ? Color.authAccent : (cornerRadii != nil ? .clear : Color.authDashedBorder),
                    lineWidth: 1.5
                )
        }
        .shadow(
            color: isFocused ? Color.authAccent.opacity(0.12) : .clear,
            radius: 6, y: 2
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}
