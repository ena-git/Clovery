import CryptoKit
import Foundation

@MainActor
protocol VaultAssetUploading: AnyObject {
    func preparePayload(
        _ payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws -> JSONValue
}

enum VaultAssetTransferError: Error, Equatable {
    case invalidFilename
    case invalidReference
    case missingLocalPhoto
    case byteSizeMismatch
    case sha256Mismatch
}

@MainActor
final class VaultAssetUploader: VaultAssetRestoring, VaultAssetUploading {
    private static let filenamePattern = #"^[A-Za-z0-9-]+\.jpg$"#
    private static let sha256Pattern = #"^[a-f0-9]{64}$"#

    private let api: VaultAssetAPIProtocol
    private let photosDirectory: URL
    private let checkpointStore: VaultSyncCheckpointStoring
    private let fileManager: FileManager
    private let assetIDGenerator: () -> UUID

    init(
        api: VaultAssetAPIProtocol,
        documentsDirectory: URL,
        checkpointStore: VaultSyncCheckpointStoring,
        fileManager: FileManager = .default,
        assetIDGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.api = api
        self.photosDirectory = documentsDirectory.appendingPathComponent("photos", isDirectory: true)
        self.checkpointStore = checkpointStore
        self.fileManager = fileManager
        self.assetIDGenerator = assetIDGenerator
    }

    func restoreMigrationAssets(
        migrationID: UUID,
        namespace: VaultSyncNamespace
    ) async throws {
        let mappings = try await api.listMigrationAssets(migrationID: migrationID)
        for mapping in mappings {
            try await restore(
                filename: mapping.sourceFilename,
                assetID: mapping.assetID,
                byteSize: mapping.byteSize,
                sha256: mapping.sha256,
                namespace: namespace
            )
        }
    }

    func restoreReferencedAssets(
        in payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws {
        for reference in try references(in: payload) {
            try await restore(
                filename: reference.filename,
                assetID: reference.assetID,
                byteSize: reference.byteSize,
                sha256: reference.sha256,
                namespace: namespace
            )
        }
    }

    func preparePayload(
        _ payload: JSONValue,
        namespace: VaultSyncNamespace
    ) async throws -> JSONValue {
        guard case var .object(entry) = payload else {
            throw VaultAssetTransferError.invalidReference
        }
        let filenames = try photoFilenames(in: entry)
        var references: [String: JSONValue] = [:]
        for filename in filenames {
            let reference = try await upload(filename: filename, namespace: namespace)
            references[filename] = .object([
                "asset_id": .string(reference.assetID.uuidString.lowercased()),
                "sha256": .string(reference.sha256),
                "byte_size": .number(Double(reference.byteSize))
            ])
        }
        if !references.isEmpty {
            entry["clovery_asset_refs"] = .object(references)
        }
        return .object(entry)
    }

    private func upload(
        filename: String,
        namespace: VaultSyncNamespace
    ) async throws -> VaultAssetReference {
        let fileURL = try validatedFileURL(filename: filename)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultAssetTransferError.missingLocalPhoto
        }
        let data = try Data(contentsOf: fileURL)
        let hash = sha256(data)
        let byteSize = Int64(data.count)
        var state = try checkpointStore.load(for: namespace)
        let existing = state.assets[filename]
        let assetID: UUID
        if let existing, existing.sha256 == hash, existing.byteSize == byteSize {
            assetID = existing.assetID
            if existing.status == .complete {
                return VaultAssetReference(
                    filename: filename,
                    assetID: assetID,
                    byteSize: byteSize,
                    sha256: hash
                )
            }
        } else {
            assetID = assetIDGenerator()
            state.assets[filename] = VaultAssetCheckpoint(
                assetID: assetID,
                sha256: hash,
                byteSize: byteSize,
                status: .pending
            )
            try checkpointStore.save(state, for: namespace)
        }

        let request = VaultAssetUploadRequest(
            assetID: assetID,
            contentType: "image/jpeg",
            byteSize: byteSize,
            sha256: hash
        )
        let ticket = try await api.startUpload(request)
        if ticket.status == .uploadRequired {
            try await api.upload(data, using: ticket)
            try await api.complete(assetID: assetID)
        }
        state = try checkpointStore.load(for: namespace)
        state.assets[filename] = VaultAssetCheckpoint(
            assetID: assetID,
            sha256: hash,
            byteSize: byteSize,
            status: .complete
        )
        try checkpointStore.save(state, for: namespace)
        return VaultAssetReference(
            filename: filename,
            assetID: assetID,
            byteSize: byteSize,
            sha256: hash
        )
    }

    private func restore(
        filename: String,
        assetID: UUID,
        byteSize: Int64,
        sha256 expectedHash: String,
        namespace: VaultSyncNamespace
    ) async throws {
        guard byteSize >= 0, isValidSHA256(expectedHash) else {
            throw VaultAssetTransferError.invalidReference
        }
        let fileURL = try validatedFileURL(filename: filename)
        if let localData = try? Data(contentsOf: fileURL),
           Int64(localData.count) == byteSize,
           sha256(localData) == expectedHash {
            try markComplete(
                filename: filename,
                assetID: assetID,
                byteSize: byteSize,
                sha256: expectedHash,
                namespace: namespace
            )
            return
        }

        let ticket = try await api.downloadTicket(assetID: assetID)
        let data = try await api.download(using: ticket)
        guard Int64(data.count) == byteSize else {
            throw VaultAssetTransferError.byteSizeMismatch
        }
        guard sha256(data) == expectedHash else {
            throw VaultAssetTransferError.sha256Mismatch
        }
        try fileManager.createDirectory(
            at: photosDirectory,
            withIntermediateDirectories: true
        )
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try markComplete(
            filename: filename,
            assetID: assetID,
            byteSize: byteSize,
            sha256: expectedHash,
            namespace: namespace
        )
    }

    private func markComplete(
        filename: String,
        assetID: UUID,
        byteSize: Int64,
        sha256: String,
        namespace: VaultSyncNamespace
    ) throws {
        var state = try checkpointStore.load(for: namespace)
        state.assets[filename] = VaultAssetCheckpoint(
            assetID: assetID,
            sha256: sha256,
            byteSize: byteSize,
            status: .complete
        )
        try checkpointStore.save(state, for: namespace)
    }

    private func references(in payload: JSONValue) throws -> [VaultAssetReference] {
        guard case let .object(entry) = payload else { return [] }
        guard let rawReferences = entry["clovery_asset_refs"] else { return [] }
        guard case let .object(references) = rawReferences else {
            throw VaultAssetTransferError.invalidReference
        }
        return try references.map { filename, value in
            guard case let .object(reference) = value,
                  let assetIDString = reference.stringValue(for: "asset_id"),
                  let assetID = UUID(uuidString: assetIDString),
                  let sha256 = reference.stringValue(for: "sha256"),
                  case let .number(rawByteSize)? = reference["byte_size"],
                  rawByteSize.rounded() == rawByteSize,
                  rawByteSize >= 0,
                  rawByteSize <= Double(Int64.max)
            else {
                throw VaultAssetTransferError.invalidReference
            }
            return VaultAssetReference(
                filename: filename,
                assetID: assetID,
                byteSize: Int64(rawByteSize),
                sha256: sha256
            )
        }
    }

    private func photoFilenames(in entry: [String: JSONValue]) throws -> [String] {
        guard let photos = entry["photos"] else { return [] }
        guard case let .array(values) = photos else {
            throw VaultAssetTransferError.invalidReference
        }
        return try values.map { value in
            guard case let .string(filename) = value else {
                throw VaultAssetTransferError.invalidReference
            }
            _ = try validatedFileURL(filename: filename)
            return filename
        }
    }

    private func validatedFileURL(filename: String) throws -> URL {
        guard filename.range(of: Self.filenamePattern, options: .regularExpression) != nil else {
            throw VaultAssetTransferError.invalidFilename
        }
        return photosDirectory.appendingPathComponent(filename)
    }

    private func isValidSHA256(_ value: String) -> Bool {
        value.range(of: Self.sha256Pattern, options: .regularExpression) != nil
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct VaultAssetReference {
    let filename: String
    let assetID: UUID
    let byteSize: Int64
    let sha256: String
}
