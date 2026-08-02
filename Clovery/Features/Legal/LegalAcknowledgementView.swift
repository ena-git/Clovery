import SwiftUI

struct LegalAcknowledgementView: View {
    @Binding var isAccepted: Bool
    @State private var presentedDocument: LegalDocument?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                isAccepted.toggle()
            } label: {
                Image(systemName: isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(.authInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAccepted ? "已同意用户协议和隐私政策" : "同意用户协议和隐私政策")

            VStack(alignment: .leading, spacing: 5) {
                Text("注册即表示你已阅读并同意")
                    .foregroundColor(.authPlaceholder)
                HStack(spacing: 10) {
                    legalButton(.terms)
                    legalButton(.privacy)
                }
            }
            .cloveryFont(.caption)
            .padding(.top, 4)
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
