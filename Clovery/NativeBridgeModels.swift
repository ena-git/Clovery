enum BoardPurchaseOutcome: String, Sendable, Equatable {
    case success
    case cancelled
    case pending
    case failed
}

enum PhotoSaveOutcome: String, Sendable, Equatable {
    case success
    case permissionDenied
    case failed
    case invalidImage
}

enum BoardRestoreOutcome: String, Sendable, Equatable {
    case restored
    case notFound
    case failed
}
