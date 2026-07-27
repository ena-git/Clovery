import CryptoKit
import Foundation

struct VaultSyncConflictResolver {
    func makeConflictCopy(
        operation: VaultSyncOperation,
        namespace: VaultSyncNamespace
    ) throws -> VaultSyncOperation {
        let payloadHash = try VaultPayloadHash.make(operation.payload)
        let entryID = deterministicUUID(
            "conflict-entry:\(namespace.accountID):\(namespace.vaultID):\(operation.entryID):\(payloadHash)"
        )
        let operationID = deterministicUUID("conflict-operation:\(entryID.uuidString.lowercased())")
        guard case var .object(payload) = operation.payload else {
            throw VaultSyncCoordinatorError.invalidServerDecision
        }
        payload["id"] = .string(entryID.uuidString.lowercased())
        return VaultSyncOperation(
            operationID: operationID,
            entryID: entryID.uuidString.lowercased(),
            baseRevision: 0,
            payload: .object(payload),
            deleted: false
        )
    }

    private func deterministicUUID(_ seed: String) -> UUID {
        var hex = SHA256.hash(data: Data(seed.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let versionIndex = hex.index(hex.startIndex, offsetBy: 12)
        let variantIndex = hex.index(hex.startIndex, offsetBy: 16)
        hex.replaceSubrange(versionIndex...versionIndex, with: "5")
        hex.replaceSubrange(variantIndex...variantIndex, with: "8")
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value)!
    }
}
