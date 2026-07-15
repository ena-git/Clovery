import Photos
import UIKit

protocol PhotoLibrarySaving {
    func savePNG(_ data: Data, completion: @escaping (PhotoSaveOutcome) -> Void)
}

struct PhotoLibraryClient {
    let authorizationStatus: () -> PHAuthorizationStatus
    let requestAuthorization: (@escaping (PHAuthorizationStatus) -> Void) -> Void
    let createAsset: (Data, @escaping (Bool, Error?) -> Void) -> Void

    static let live = PhotoLibraryClient(
        authorizationStatus: {
            PHPhotoLibrary.authorizationStatus(for: .addOnly)
        },
        requestAuthorization: { completion in
            PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: completion)
        },
        createAsset: { data, completion in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                completion(success, error)
            }
        }
    )
}

final class PhotoLibrarySaver: PhotoLibrarySaving {
    private let client: PhotoLibraryClient

    init(client: PhotoLibraryClient = .live) {
        self.client = client
    }

    func savePNG(_ data: Data, completion: @escaping (PhotoSaveOutcome) -> Void) {
        guard UIImage(data: data) != nil else {
            completion(.invalidImage)
            return
        }

        handle(
            client.authorizationStatus(),
            data: data,
            canRequestAuthorization: true,
            completion: completion
        )
    }

    private func handle(
        _ status: PHAuthorizationStatus,
        data: Data,
        canRequestAuthorization: Bool,
        completion: @escaping (PhotoSaveOutcome) -> Void
    ) {
        switch status {
        case .authorized, .limited:
            client.createAsset(data) { success, _ in
                completion(success ? .success : .failed)
            }
        case .notDetermined:
            guard canRequestAuthorization else {
                completion(.failed)
                return
            }
            client.requestAuthorization { updatedStatus in
                self.handle(
                    updatedStatus,
                    data: data,
                    canRequestAuthorization: false,
                    completion: completion
                )
            }
        case .denied, .restricted:
            completion(.permissionDenied)
        @unknown default:
            completion(.failed)
        }
    }
}
