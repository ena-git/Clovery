import CryptoKit
import Foundation
import XCTest
@testable import Clovery

@MainActor
final class VaultAssetUploaderTests: XCTestCase {
    func testMigrationRestoreSkipsVerifiedPhotoAndAtomicallyReplacesCorruptPhoto() async throws {
        let directory = temporaryDirectory()
        let photos = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let valid = Data("valid".utf8)
        let repaired = Data("repaired".utf8)
        try valid.write(to: photos.appendingPathComponent("photo-valid.jpg"))
        try Data("corrupt".utf8).write(to: photos.appendingPathComponent("photo-corrupt.jpg"))
        let validID = UUID()
        let corruptID = UUID()
        let api = VaultAssetAPISpy()
        api.migrationAssets = [
            mapping(filename: "photo-valid.jpg", assetID: validID, data: valid),
            mapping(filename: "photo-corrupt.jpg", assetID: corruptID, data: repaired)
        ]
        api.downloads[corruptID] = repaired
        let namespace = VaultSyncNamespace(accountID: "account", vaultID: "vault")
        let checkpoints = VaultSyncCheckpointStore(baseDirectory: directory.appendingPathComponent("sync"))
        let uploader = VaultAssetUploader(
            api: api,
            documentsDirectory: directory,
            checkpointStore: checkpoints
        )

        try await uploader.restoreMigrationAssets(migrationID: UUID(), namespace: namespace)

        XCTAssertEqual(api.downloadTicketIDs, [corruptID])
        XCTAssertEqual(try Data(contentsOf: photos.appendingPathComponent("photo-valid.jpg")), valid)
        XCTAssertEqual(try Data(contentsOf: photos.appendingPathComponent("photo-corrupt.jpg")), repaired)
        XCTAssertEqual(try checkpoints.load(for: namespace).assets.count, 2)
    }

    func testFailedRestorePreservesPriorFileAndRejectsUnsafeFilename() async throws {
        let directory = temporaryDirectory()
        let photos = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let prior = Data("prior".utf8)
        let fileURL = photos.appendingPathComponent("photo-safe.jpg")
        try prior.write(to: fileURL)
        let api = VaultAssetAPISpy()
        let assetID = UUID()
        api.migrationAssets = [mapping(filename: "photo-safe.jpg", assetID: assetID, data: Data("expected".utf8))]
        api.downloads[assetID] = Data("wrong".utf8)
        let uploader = VaultAssetUploader(
            api: api,
            documentsDirectory: directory,
            checkpointStore: VaultSyncCheckpointStore(baseDirectory: directory.appendingPathComponent("sync"))
        )

        await XCTAssertThrowsErrorAsync {
            try await uploader.restoreMigrationAssets(
                migrationID: UUID(),
                namespace: VaultSyncNamespace(accountID: "account", vaultID: "vault")
            )
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), prior)
        api.migrationAssets = [mapping(filename: "../escape.jpg", assetID: UUID(), data: Data())]
        await XCTAssertThrowsErrorAsync {
            try await uploader.restoreMigrationAssets(
                migrationID: UUID(),
                namespace: VaultSyncNamespace(accountID: "account", vaultID: "vault")
            )
        }
    }

    func testUploadPersistsAssetIDBeforeNetworkAndReusesItAfterRetry() async throws {
        let directory = temporaryDirectory()
        let photos = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let bytes = Data("photo".utf8)
        try bytes.write(to: photos.appendingPathComponent("photo-1.jpg"))
        let api = VaultAssetAPISpy()
        api.startUploadError = TestAssetError.offline
        let namespace = VaultSyncNamespace(accountID: "account", vaultID: "vault")
        let checkpoints = VaultSyncCheckpointStore(baseDirectory: directory.appendingPathComponent("sync"))
        let generatedID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let uploader = VaultAssetUploader(
            api: api,
            documentsDirectory: directory,
            checkpointStore: checkpoints,
            assetIDGenerator: { generatedID }
        )
        let payload: JSONValue = .object([
            "id": .string("entry"),
            "photos": .array([.string("photo-1.jpg")])
        ])

        await XCTAssertThrowsErrorAsync {
            _ = try await uploader.preparePayload(payload, namespace: namespace)
        }
        XCTAssertEqual(try checkpoints.load(for: namespace).assets["photo-1.jpg"]?.assetID, generatedID)

        api.startUploadError = nil
        api.uploadStatus = .complete
        let prepared = try await uploader.preparePayload(payload, namespace: namespace)

        XCTAssertEqual(api.uploadRequests.map(\.assetID), [generatedID, generatedID])
        guard case let .object(entry) = prepared,
              case let .object(refs)? = entry["clovery_asset_refs"],
              case let .object(reference)? = refs["photo-1.jpg"] else {
            return XCTFail("Expected private asset references.")
        }
        XCTAssertEqual(reference["asset_id"], .string(generatedID.uuidString.lowercased()))
        XCTAssertEqual(reference["byte_size"], .number(Double(bytes.count)))
        XCTAssertEqual(try checkpoints.load(for: namespace).assets["photo-1.jpg"]?.status, .complete)
    }

    private func mapping(filename: String, assetID: UUID, data: Data) -> VaultMigrationAsset {
        VaultMigrationAsset(
            sourceFilename: filename,
            assetID: assetID,
            byteSize: Int64(data.count),
            sha256: sha256(data)
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

@MainActor
private final class VaultAssetAPISpy: VaultAssetAPIProtocol {
    var migrationAssets: [VaultMigrationAsset] = []
    var downloads: [UUID: Data] = [:]
    var startUploadError: Error?
    var uploadStatus: VaultAssetUploadStatus = .uploadRequired
    private(set) var downloadTicketIDs: [UUID] = []
    private(set) var uploadRequests: [VaultAssetUploadRequest] = []

    func listMigrationAssets(migrationID: UUID) async throws -> [VaultMigrationAsset] {
        migrationAssets
    }

    func startUpload(_ request: VaultAssetUploadRequest) async throws -> VaultAssetUploadTicket {
        uploadRequests.append(request)
        if let startUploadError { throw startUploadError }
        return VaultAssetUploadTicket(
            assetID: request.assetID,
            status: uploadStatus,
            uploadURL: uploadStatus == .uploadRequired ? URL(string: "https://objects.example/upload") : nil,
            requiredHeaders: [:],
            expiresAt: nil
        )
    }

    func upload(_ data: Data, using ticket: VaultAssetUploadTicket) async throws {}
    func complete(assetID: UUID) async throws {}

    func downloadTicket(assetID: UUID) async throws -> VaultAssetDownloadTicket {
        downloadTicketIDs.append(assetID)
        return VaultAssetDownloadTicket(
            assetID: assetID,
            downloadURL: URL(string: "https://objects.example/\(assetID)")!,
            expiresAt: "2026-07-27T00:15:00Z"
        )
    }

    func download(using ticket: VaultAssetDownloadTicket) async throws -> Data {
        downloads[ticket.assetID] ?? Data()
    }
}

private enum TestAssetError: Error {
    case offline
}
