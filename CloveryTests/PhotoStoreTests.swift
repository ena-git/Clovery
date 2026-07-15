import Foundation
import XCTest
@testable import Clovery

final class PhotoStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: PhotoStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        store = PhotoStore(baseDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSaveAndLoadRoundTripsJPEGBase64() throws {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let base64 = jpegData.base64EncodedString()

        try store.save(
            filename: "photo-0001.jpg",
            dataURL: "data:image/jpeg;base64,\(base64)"
        )

        XCTAssertEqual(try store.load(filename: "photo-0001.jpg"), base64)
    }

    func testGarbageCollectKeepsReferencedFiles() throws {
        let dataURL = "data:image/jpeg;base64,\(Data([1, 2, 3]).base64EncodedString())"
        try store.save(filename: "photo-keep.jpg", dataURL: dataURL)
        try store.save(filename: "photo-remove.jpg", dataURL: dataURL)

        try store.garbageCollect(keeping: ["photo-keep.jpg"])

        XCTAssertNoThrow(try store.load(filename: "photo-keep.jpg"))
        XCTAssertThrowsError(try store.load(filename: "photo-remove.jpg"))
    }

    func testRejectsInvalidFilename() {
        let dataURL = "data:image/jpeg;base64,\(Data([1]).base64EncodedString())"

        XCTAssertThrowsError(try store.save(filename: "../escape.jpg", dataURL: dataURL))
        XCTAssertThrowsError(try store.load(filename: "photo name.jpg"))
    }

    func testRejectsInvalidBase64() {
        XCTAssertThrowsError(
            try store.save(filename: "photo-0001.jpg", dataURL: "data:image/jpeg;base64,not-base64!")
        )
    }
}
