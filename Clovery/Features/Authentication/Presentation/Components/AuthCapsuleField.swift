import SwiftUI
import UIKit

struct AuthCapsuleField<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 36)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 78)
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

    var body: some View {
        AuthCapsuleField {
            Group {
                if isSecure {
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
            .cloveryFont(.body)
            .foregroundColor(.authInk)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
        }
    }
}
