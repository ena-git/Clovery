import Foundation

protocol PhotoStoring {
    func save(filename: String, dataURL: String) throws
    func load(filename: String) throws -> String
    func garbageCollect(keeping filenames: Set<String>) throws
}

enum PhotoStoreError: Error {
    case invalidFilename
    case invalidDataURL
    case invalidBase64
    case documentsDirectoryUnavailable

    var code: String {
        switch self {
        case .invalidFilename: "invalidFilename"
        case .invalidDataURL: "invalidDataURL"
        case .invalidBase64: "invalidBase64"
        case .documentsDirectoryUnavailable: "storageUnavailable"
        }
    }
}

struct PhotoStore: PhotoStoring {
    private static let jpegDataURLPrefix = "data:image/jpeg;base64,"
    private static let filenamePattern = #"^[A-Za-z0-9-]+\.jpg$"#

    private let fileManager: FileManager
    private let photosDirectory: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager

        if let baseDirectory {
            photosDirectory = baseDirectory.appendingPathComponent("photos", isDirectory: true)
        } else if let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            photosDirectory = documentsDirectory.appendingPathComponent("photos", isDirectory: true)
        } else {
            photosDirectory = nil
        }
    }

    func save(filename: String, dataURL: String) throws {
        let fileURL = try validatedFileURL(filename: filename)
        guard dataURL.hasPrefix(Self.jpegDataURLPrefix) else {
            throw PhotoStoreError.invalidDataURL
        }

        let encoded = String(dataURL.dropFirst(Self.jpegDataURLPrefix.count))
        guard let data = Data(base64Encoded: encoded) else {
            throw PhotoStoreError.invalidBase64
        }

        _ = try ensurePhotosDirectory()
        try data.write(to: fileURL, options: .atomic)
    }

    func load(filename: String) throws -> String {
        let fileURL = try validatedFileURL(filename: filename)
        let data = try Data(contentsOf: fileURL)
        return data.base64EncodedString()
    }

    func garbageCollect(keeping filenames: Set<String>) throws {
        for filename in filenames {
            _ = try validatedFileURL(filename: filename)
        }

        let photosDirectory = try ensurePhotosDirectory()
        let files = try fileManager.contentsOfDirectory(
            at: photosDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in files {
            let filename = fileURL.lastPathComponent
            guard isValidFilename(filename), !filenames.contains(filename) else { continue }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func ensurePhotosDirectory() throws -> URL {
        guard let photosDirectory else {
            throw PhotoStoreError.documentsDirectoryUnavailable
        }
        try fileManager.createDirectory(
            at: photosDirectory,
            withIntermediateDirectories: true
        )
        return photosDirectory
    }

    private func validatedFileURL(filename: String) throws -> URL {
        guard isValidFilename(filename) else {
            throw PhotoStoreError.invalidFilename
        }
        guard let photosDirectory else {
            throw PhotoStoreError.documentsDirectoryUnavailable
        }
        return photosDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func isValidFilename(_ filename: String) -> Bool {
        filename.range(of: Self.filenamePattern, options: .regularExpression) != nil
    }
}
