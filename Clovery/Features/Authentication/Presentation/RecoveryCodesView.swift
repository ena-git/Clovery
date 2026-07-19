import SwiftUI
import UIKit

struct RecoveryCodesView: View {
    let codes: [String]
    let acknowledge: () -> Void
    @State private var confirmedSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("恢复码")
                    .font(.authTitle)
                    .foregroundColor(.authInk)
                    .multilineTextAlignment(.center)

                Text("请保存这 8 个一次性恢复码。Clovery 之后无法再次显示。")
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

                Button("复制全部") {
                    UIPasteboard.general.string = codes.joined(separator: "\n")
                }
                .font(.authAction)
                .foregroundColor(.authInk)
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Toggle("我已保存恢复码", isOn: $confirmedSaved)
                    .font(.authCaption)
                    .tint(.authInk)
                    .padding(.horizontal, 36)

                Button(action: acknowledge) {
                    Text("继续")
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
