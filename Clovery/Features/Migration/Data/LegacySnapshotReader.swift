import Foundation
import WebKit

struct LegacyWebSnapshot: Equatable {
    let entriesJSON: String
    let deletedIDsJSON: String
}

@MainActor
protocol LegacyWebSnapshotReading: AnyObject {
    func readSnapshot() async throws -> LegacyWebSnapshot
}

@MainActor
protocol LegacyCloudSnapshotPulling: AnyObject {
    func pullAllLegacyEntries(photosDirectory: URL) async throws -> [[String: Any]]
}

@MainActor
final class LegacySnapshotReader {
    private let documentsDirectory: URL
    private let sourceReader: LegacySnapshotSources
    private let webReader: LegacyWebSnapshotReading
    private let cloudPuller: LegacyCloudSnapshotPulling
    private let fileManager: FileManager

    init(
        documentsDirectory: URL,
        userDefaults: UserDefaults = .standard,
        keyValueStore: LegacyKeyValueReading = NSUbiquitousKeyValueStore.default,
        webReader: LegacyWebSnapshotReading,
        cloudPuller: LegacyCloudSnapshotPulling,
        fileManager: FileManager = .default
    ) {
        self.documentsDirectory = documentsDirectory
        self.sourceReader = LegacySnapshotSources(
            documentsDirectory: documentsDirectory,
            userDefaults: userDefaults,
            keyValueStore: keyValueStore,
            fileManager: fileManager
        )
        self.webReader = webReader
        self.cloudPuller = cloudPuller
        self.fileManager = fileManager
    }

    func readSources() async -> LegacySnapshotReadResult {
        let local = sourceReader.readLocalSources()
        var sources = local.sources
        var warnings = local.warnings

        do {
            let web = try await webReader.readSnapshot()
            sources.append(
                LegacySnapshotSourceData(
                    kind: .webLocalStorage,
                    entriesJSON: web.entriesJSON,
                    deletedIDsJSON: web.deletedIDsJSON,
                    name: nil
                )
            )
        } catch {
            warnings.append(
                LegacySnapshotWarning(
                    source: .webLocalStorage,
                    code: "legacy_web_snapshot_unavailable",
                    retryable: true
                )
            )
        }

        do {
            let photosDirectory = documentsDirectory
                .appendingPathComponent("photos", isDirectory: true)
            try fileManager.createDirectory(
                at: photosDirectory,
                withIntermediateDirectories: true
            )
            let entries = try await cloudPuller.pullAllLegacyEntries(
                photosDirectory: photosDirectory
            )
            let data = try JSONSerialization.data(
                withJSONObject: entries,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            sources.append(
                LegacySnapshotSourceData(
                    kind: .cloudKit,
                    entriesJSON: String(decoding: data, as: UTF8.self),
                    deletedIDsJSON: "[]",
                    name: nil
                )
            )
        } catch {
            warnings.append(
                LegacySnapshotWarning(
                    source: .cloudKit,
                    code: "legacy_cloudkit_pull_unavailable",
                    retryable: true
                )
            )
        }

        return LegacySnapshotReadResult(sources: sources, warnings: warnings)
    }
}

@MainActor
final class LegacyWebLocalStorageReader: NSObject, LegacyWebSnapshotReading {
    static let extractionScript = """
    JSON.stringify({
      entries: localStorage.getItem('clovery_entries') || '[]',
      deletedIDs: localStorage.getItem('clovery_deleted_ids') || '[]'
    })
    """

    private let htmlURL: URL?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<LegacyWebSnapshot, Error>?

    init(htmlURL: URL? = Bundle.main.url(forResource: "Clover Diary", withExtension: "html")) {
        self.htmlURL = htmlURL
    }

    func readSnapshot() async throws -> LegacyWebSnapshot {
        guard continuation == nil else {
            throw LegacyWebSnapshotError.readAlreadyInProgress
        }
        guard let htmlURL else {
            throw LegacyWebSnapshotError.htmlMissing
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(
                htmlURL,
                allowingReadAccessTo: htmlURL.deletingLastPathComponent()
            )
        }
    }

    private func finish(_ result: Result<LegacyWebSnapshot, Error>) {
        let continuation = continuation
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation?.resume(with: result)
    }
}

extension LegacyWebLocalStorageReader: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.extractionScript) { [weak self] value, error in
            guard let self else { return }
            if let error {
                finish(.failure(error))
                return
            }
            do {
                guard let raw = value as? String,
                      let data = raw.data(using: .utf8) else {
                    throw LegacyWebSnapshotError.invalidPayload
                }
                let payload = try JSONDecoder().decode(
                    LegacyWebSnapshotPayload.self,
                    from: data
                )
                finish(
                    .success(
                        LegacyWebSnapshot(
                            entriesJSON: payload.entries,
                            deletedIDsJSON: payload.deletedIDs
                        )
                    )
                )
            } catch {
                finish(.failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }
}

private struct LegacyWebSnapshotPayload: Decodable {
    let entries: String
    let deletedIDs: String
}

private enum LegacyWebSnapshotError: Error {
    case htmlMissing
    case invalidPayload
    case readAlreadyInProgress
}
