import SwiftUI

struct LegalAcknowledgementView: View {
    @Binding var isAccepted: Bool
    @State private var presentedDocument: LegalDocument?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                isAccepted.toggle()
            } label: {
                Image(systemName: isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(.authInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAccepted ? "已同意用户协议和隐私政策" : "同意用户协议和隐私政策")

            Text("注册即同意")
                .foregroundColor(.authPlaceholder)

            legalButton(.terms)

            Text("·")
                .foregroundColor(.authPlaceholder)

            legalButton(.privacy)
        }
        .cloveryFont(.footnote)
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSafariView(document: document)
                .ignoresSafeArea()
        }
    }

    private func legalButton(_ document: LegalDocument) -> some View {
        Button(document.title) {
            presentedDocument = document
        }
        .foregroundColor(.authInk)
        .buttonStyle(.plain)
        .accessibilityHint("在应用内打开")
    }
}

struct LegalDocumentLinksView: View {
    @State private var presentedDocument: LegalDocument?

    var body: some View {
        HStack(spacing: 18) {
            legalButton(.terms)
            legalButton(.privacy)
        }
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSafariView(document: document)
                .ignoresSafeArea()
        }
    }

    private func legalButton(_ document: LegalDocument) -> some View {
        Button(document.title) {
            presentedDocument = document
        }
        .buttonStyle(.plain)
        .foregroundColor(.authInk)
        .frame(minHeight: 44)
        .accessibilityHint("在应用内打开")
    }
}
