import SwiftUI

extension Color {
    static let authBackground = Color("AuthBackground")
    static let authSurface = Color("AuthSurface")
    static let authInk = Color("AuthInk")
    static let authPlaceholder = Color("AuthPlaceholder")
    static let authDashedBorder = Color("AuthDashedBorder")
}

extension Font {
    static let authTitle = Font.custom("Gaegu-Regular", size: 48, relativeTo: .largeTitle)
    static let authAction = Font.custom("Gaegu-Regular", size: 24, relativeTo: .title3)
    static let authBody = Font.custom("Gaegu-Regular", size: 24, relativeTo: .body)
    static let authCaption = Font.custom("Gaegu-Regular", size: 16, relativeTo: .caption)
}
