struct VaultDiarySnapshot: Equatable {
    var entries: [[String: String]]
    var deletedIDs: [String]
    var name: String?
}
