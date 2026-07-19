import Foundation

enum AuthenticationValidationIssue: Equatable {
    case invalidCloveryID
    case invalidPassword
    case passwordsDoNotMatch
}

enum AuthenticationValidation {
    private static let cloverIDPattern = "^[a-z][a-z0-9_]{3,23}$"

    static func normalizedCloveryID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidCloveryID(_ value: String) -> Bool {
        let normalized = normalizedCloveryID(value)
        return normalized.range(of: cloverIDPattern, options: .regularExpression) != nil
    }

    static func isValidPassword(_ value: String) -> Bool {
        let length = value.unicodeScalars.count
        return (8...256).contains(length)
    }
}
