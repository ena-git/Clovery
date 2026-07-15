import Foundation

@main
struct MigrationBundleZipSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw MigrationBundleError.invalidArchive
        }

        let documentsDirectory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let photosDirectory = documentsDirectory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: photosDirectory,
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(
            to: photosDirectory.appendingPathComponent("photo-smoke.jpg")
        )

        let result = try MigrationBundleExporter(
            documentsDirectory: documentsDirectory
        ).export(
            entriesJSON: #"[{"id":"smoke","photos":["photo-smoke.jpg"]}]"#
        )
        print(result.archiveURL.path)
    }
}
