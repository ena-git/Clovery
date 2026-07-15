import Photos
import XCTest
@testable import Clovery

final class PhotoLibrarySaverTests: XCTestCase {
    private let validPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4n8AAAAASUVORK5CYII="
    )!

    func testDeniedPermissionDoesNotAttemptWrite() {
        var writeCount = 0
        let saver = PhotoLibrarySaver(client: PhotoLibraryClient(
            authorizationStatus: { .denied },
            requestAuthorization: { completion in completion(.denied) },
            createAsset: { _, completion in writeCount += 1; completion(true, nil) }
        ))

        let result = expectation(description: "result")
        saver.savePNG(validPNG) { outcome in
            XCTAssertEqual(outcome, .permissionDenied)
            result.fulfill()
        }
        wait(for: [result], timeout: 1)
        XCTAssertEqual(writeCount, 0)
    }

    func testNotDeterminedThenAuthorizedWritesAsset() {
        var writeCount = 0
        let saver = PhotoLibrarySaver(client: PhotoLibraryClient(
            authorizationStatus: { .notDetermined },
            requestAuthorization: { completion in completion(.authorized) },
            createAsset: { _, completion in writeCount += 1; completion(true, nil) }
        ))

        let result = expectation(description: "result")
        saver.savePNG(validPNG) { outcome in
            XCTAssertEqual(outcome, .success)
            result.fulfill()
        }
        wait(for: [result], timeout: 1)
        XCTAssertEqual(writeCount, 1)
    }

    func testInvalidImageAndWriteFailureAreVisible() {
        let invalid = PhotoLibrarySaver(client: authorizedClient(writeSucceeds: true))
        let invalidResult = expectation(description: "invalid")
        invalid.savePNG(Data("not-an-image".utf8)) { outcome in
            XCTAssertEqual(outcome, .invalidImage)
            invalidResult.fulfill()
        }

        let failed = PhotoLibrarySaver(client: authorizedClient(writeSucceeds: false))
        let failedResult = expectation(description: "failed")
        failed.savePNG(validPNG) { outcome in
            XCTAssertEqual(outcome, .failed)
            failedResult.fulfill()
        }

        wait(for: [invalidResult, failedResult], timeout: 1)
    }

    private func authorizedClient(writeSucceeds: Bool) -> PhotoLibraryClient {
        PhotoLibraryClient(
            authorizationStatus: { .authorized },
            requestAuthorization: { completion in completion(.authorized) },
            createAsset: { _, completion in completion(writeSucceeds, nil) }
        )
    }
}
