import UIKit

protocol ImageSharing {
    func sharePNG(_ data: Data)
}

protocol AppSettingsOpening {
    func open()
}

protocol ImageExporting {
    func handle(
        action: String,
        dataURL: String,
        saveCompletion: @escaping (PhotoSaveOutcome) -> Void
    )
    func openSettings()
}

final class ImageExportService: ImageExporting {
    private let photoLibrary: PhotoLibrarySaving
    private let sharePresenter: ImageSharing
    private let settingsOpener: AppSettingsOpening

    init(
        photoLibrary: PhotoLibrarySaving = PhotoLibrarySaver(),
        sharePresenter: ImageSharing = SystemImageSharePresenter(),
        settingsOpener: AppSettingsOpening = SystemAppSettingsOpener()
    ) {
        self.photoLibrary = photoLibrary
        self.sharePresenter = sharePresenter
        self.settingsOpener = settingsOpener
    }

    func handle(
        action: String,
        dataURL: String,
        saveCompletion: @escaping (PhotoSaveOutcome) -> Void
    ) {
        let prefix = "data:image/png;base64,"
        guard dataURL.hasPrefix(prefix),
              let data = Data(base64Encoded: String(dataURL.dropFirst(prefix.count))),
              UIImage(data: data) != nil else {
            if action == "save" {
                saveCompletion(.invalidImage)
            }
            return
        }

        switch action {
        case "save":
            photoLibrary.savePNG(data, completion: saveCompletion)
        case "share":
            sharePresenter.sharePNG(data)
        default:
            break
        }
    }

    func openSettings() {
        settingsOpener.open()
    }
}

final class SystemImageSharePresenter: ImageSharing {
    func sharePNG(_ data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clovery-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        DispatchQueue.main.async {
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController else { return }

            let controller = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            controller.popoverPresentationController?.sourceView = rootViewController.view
            rootViewController.present(controller, animated: true)
        }
    }
}

final class SystemAppSettingsOpener: AppSettingsOpening {
    func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }
}
