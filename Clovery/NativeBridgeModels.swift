enum BoardPurchaseOutcome: String, Sendable {
    case success
    case cancelled
    case pending
    case failed
}

enum PhotoSaveOutcome: String, Sendable {
    case success
    case permissionDenied
    case failed
    case invalidImage
}
