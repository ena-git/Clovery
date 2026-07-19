import SwiftUI
import UIKit

struct RecoveryCodesView: View {
    let codes: [String]
    let acknowledge: () -> Void
    @State private var confirmedSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("RECOVERY CODES")
                    .font(.authTitle)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)

                Text("Please save these eight one-time codes. Clovery cannot show them again.")
                    .font(.authAction)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)

                AuthDashedCard(height: 330) {
                    VStack(spacing: 10) {
                        ForEach(codes, id: \.self) { code in
                            Text(code)
                                .font(.authAction)
                                .foregroundColor(.authInk)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: 347)

                Button("COPY ALL") {
                    UIPasteboard.general.string = codes.joined(separator: "\n")
                }
                .font(.authAction)
                .foregroundColor(.authInk)
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Toggle("I saved my recovery codes", isOn: $confirmedSaved)
                    .font(.authCaption)
                    .tint(.authInk)
                    .padding(.horizontal, 36)

                Button(action: acknowledge) {
                    Text("CONTINUE")
                        .font(.authAction)
                        .foregroundColor(.authInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color.authSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!confirmedSaved)
                .opacity(confirmedSaved ? 1 : 0.45)
                .padding(.horizontal, 30)
            }
            .padding(.vertical, 34)
        }
        .background(Color.authBackground.ignoresSafeArea())
    }
}
