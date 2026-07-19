import SwiftUI

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(AuthenticationAsset.divider.rawValue)
                .resizable()
                .frame(width: 108, height: 4)
            Text("或")
                .cloveryFont(.caption)
                .foregroundColor(.authPlaceholder)
                .frame(width: 24)
            Image(AuthenticationAsset.divider.rawValue)
                .resizable()
                .frame(width: 108, height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("其他登录方式")
    }
}
