import XCTest
@testable import Clovery

final class ImageExportServiceTests: XCTestCase {
    private let validDataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4n8AAAAASUVORK5CYII="

    func testSaveRoutesToPhotoLibraryAndReturnsOutcome() {
        let photoLibrary = PhotoLibrarySpy(outcome: .success)
        let share = ImageShareSpy()
        let settings = AppSettingsSpy()
        let service = ImageExportService(
            photoLibrary: photoLibrary,
            sharePresenter: share,
            settingsOpener: settings
        )

        let result = expectation(description: "save")
        service.handle(action: "save", dataURL: validDataURL) { outcome in
            XCTAssertEqual(outcome, .success)
            result.fulfill()
        }
        wait(for: [result], timeout: 1)
        XCTAssertEqual(photoLibrary.savedImageCount, 1)
        XCTAssertEqual(share.sharedImageCount, 0)
    }

    func testShareAndSettingsUseSeparateSystemCapabilities() {
        let photoLibrary = PhotoLibrarySpy(outcome: .success)
        let share = ImageShareSpy()
        let settings = AppSettingsSpy()
        let service = ImageExportService(
            photoLibrary: photoLibrary,
            sharePresenter: share,
            settingsOpener: settings
        )

        service.handle(action: "share", dataURL: validDataURL) { _ in
            XCTFail("share must not report a photo-library save")
        }
        service.openSettings()

        XCTAssertEqual(photoLibrary.savedImageCount, 0)
        XCTAssertEqual(share.sharedImageCount, 1)
        XCTAssertEqual(settings.openCount, 1)
    }

    func testInvalidDataURLReturnsInvalidImage() {
        let service = ImageExportService(
            photoLibrary: PhotoLibrarySpy(outcome: .success),
            sharePresenter: ImageShareSpy(),
            settingsOpener: AppSettingsSpy()
        )
        let result = expectation(description: "invalid")
        service.handle(action: "save", dataURL: "data:text/plain;base64,QQ==") { outcome in
            XCTAssertEqual(outcome, .invalidImage)
            result.fulfill()
        }
        wait(for: [result], timeout: 1)
    }
}

private final class PhotoLibrarySpy: PhotoLibrarySaving {
    let outcome: PhotoSaveOutcome
    private(set) var savedImageCount = 0

    init(outcome: PhotoSaveOutcome) {
        self.outcome = outcome
    }

    func savePNG(_ data: Data, completion: @escaping (PhotoSaveOutcome) -> Void) {
        savedImageCount += 1
        completion(outcome)
    }
}

private final class ImageShareSpy: ImageSharing {
    private(set) var sharedImageCount = 0
    func sharePNG(_ data: Data) { sharedImageCount += 1 }
}

private final class AppSettingsSpy: AppSettingsOpening {
    private(set) var openCount = 0
    func open() { openCount += 1 }
}
