import SafariServices
import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "隐私政策"
        case .terms: "用户协议"
        }
    }

    var url: URL {
        switch self {
        case .privacy:
            URL(string: "https://api.clovery.cn/v1/legal/privacy")!
        case .terms:
            URL(string: "https://api.clovery.cn/v1/legal/terms")!
        }
    }
}

struct LegalDocumentSafariView: UIViewControllerRepresentable {
    let document: LegalDocument

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: document.url)
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}
