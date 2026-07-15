import Foundation

struct MigrationBundleManifest: Codable, Equatable {
    let formatVersion: Int
    let exportedAt: String
    let entriesFile: String
    let entriesSHA256: String
    let entryCount: Int
    let entries: [MigrationEntryManifest]
    let deletedIDsFile: String
    let deletedIDsSHA256: String
    let deletedCount: Int
    let deletedIDs: [String]
    let photos: [MigrationPhotoManifest]
    let sources: [String]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
        case entriesFile = "entries_file"
        case entriesSHA256 = "entries_sha256"
        case entryCount = "entry_count"
        case entries
        case deletedIDsFile = "deleted_ids_file"
        case deletedIDsSHA256 = "deleted_ids_sha256"
        case deletedCount = "deleted_count"
        case deletedIDs = "deleted_ids"
        case photos
        case sources
    }
}

struct MigrationEntryManifest: Codable, Equatable {
    let entryID: String
    let sha256: String
    let bytes: Int

    enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case sha256
        case bytes
    }
}

struct MigrationPhotoManifest: Codable, Equatable {
    let filename: String
    let sha256: String
    let bytes: Int
}

struct MigrationBundleExportResult: Equatable {
    let migrationID: String
    let archiveURL: URL
    let entryCount: Int
    let photoCount: Int
}

enum MigrationBundleError: Error {
    case invalidEntriesJSON
    case invalidDeletedIDsJSON
    case invalidEntryID(String)
    case duplicateEntryID(String)
    case activeEntryMarkedDeleted(String)
    case invalidSource(String)
    case invalidPhotoFilename(String)
    case missingPhoto(String)
    case invalidManifest
    case entryCountMismatch
    case entriesHashMismatch
    case deletedIDsHashMismatch
    case photoSizeMismatch(String)
    case photoHashMismatch(String)
    case invalidArchive
    case archiveEntryTooLarge(String)
}

enum MigrationBundleArchive {
    private struct CentralEntry {
        let name: Data
        let crc32: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    static func write(files: [String: Data], to url: URL) throws {
        var archive = Data()
        var centralEntries: [CentralEntry] = []

        for name in files.keys.sorted() {
            guard let contents = files[name],
                  let nameData = name.data(using: .utf8),
                  nameData.count <= Int(UInt16.max),
                  contents.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw MigrationBundleError.archiveEntryTooLarge(name)
            }

            let checksum = crc32(contents)
            let size = UInt32(contents.count)
            let offset = UInt32(archive.count)

            archive.appendUInt32LE(0x04034B50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(checksum)
            archive.appendUInt32LE(size)
            archive.appendUInt32LE(size)
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(contents)

            centralEntries.append(
                CentralEntry(
                    name: nameData,
                    crc32: checksum,
                    size: size,
                    localHeaderOffset: offset
                )
            )
        }

        guard centralEntries.count <= Int(UInt16.max),
              archive.count <= Int(UInt32.max) else {
            throw MigrationBundleError.invalidArchive
        }

        let centralDirectoryOffset = UInt32(archive.count)
        for entry in centralEntries {
            archive.appendUInt32LE(0x02014B50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(entry.crc32)
            archive.appendUInt32LE(entry.size)
            archive.appendUInt32LE(entry.size)
            archive.appendUInt16LE(UInt16(entry.name.count))
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(0)
            archive.appendUInt32LE(entry.localHeaderOffset)
            archive.append(entry.name)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw MigrationBundleError.invalidArchive
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        let entryCount = UInt16(centralEntries.count)
        archive.appendUInt32LE(0x06054B50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(entryCount)
        archive.appendUInt16LE(entryCount)
        archive.appendUInt32LE(centralDirectorySize)
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> [String: Data] {
        let archive = try Data(contentsOf: url)
        var offset = 0
        var files: [String: Data] = [:]

        while offset + 4 <= archive.count {
            let signature = try archive.uint32LE(at: offset)
            if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            }
            guard signature == 0x04034B50, offset + 30 <= archive.count else {
                throw MigrationBundleError.invalidArchive
            }

            let flags = try archive.uint16LE(at: offset + 6)
            let compressionMethod = try archive.uint16LE(at: offset + 8)
            let checksum = try archive.uint32LE(at: offset + 14)
            let compressedSize = Int(try archive.uint32LE(at: offset + 18))
            let uncompressedSize = Int(try archive.uint32LE(at: offset + 22))
            let nameLength = Int(try archive.uint16LE(at: offset + 26))
            let extraLength = Int(try archive.uint16LE(at: offset + 28))
            guard flags == 0,
                  compressionMethod == 0,
                  compressedSize == uncompressedSize else {
                throw MigrationBundleError.invalidArchive
            }

            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= archive.count,
                  let name = String(
                    data: archive.subdata(in: nameStart..<(nameStart + nameLength)),
                    encoding: .utf8
                  ),
                  !name.isEmpty,
                  !name.hasPrefix("/"),
                  !name.split(separator: "/").contains("..") else {
                throw MigrationBundleError.invalidArchive
            }

            let contents = archive.subdata(in: dataStart..<dataEnd)
            guard crc32(contents) == checksum else {
                throw MigrationBundleError.invalidArchive
            }
            files[name] = contents
            offset = dataEnd
        }

        return files
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = (value & 1) == 1
                    ? (value >> 1) ^ 0xEDB8_8320
                    : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw MigrationBundleError.invalidArchive
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw MigrationBundleError.invalidArchive
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
