import Foundation

enum BridgeJavaScript {
    static func boardUnlockStatus(_ unlocked: Bool) -> String {
        evaluateJSONCallback(name: "window._boardUnlockStatus", payload: [unlocked])
    }

    static func boardPurchaseResult(_ outcome: BoardPurchaseOutcome) -> String {
        evaluateJSONCallback(name: "window._boardPurchaseResult", payload: [outcome.rawValue])
    }

    static func boardRestoreResult(_ outcome: BoardRestoreOutcome) -> String {
        evaluateJSONCallback(name: "window._boardRestoreResult", payload: [outcome.rawValue])
    }

    static func boardPriceResult(_ price: String) -> String {
        evaluateJSONCallback(name: "window._boardPriceResult", payload: [price])
    }

    static func photoSaveResult(_ outcome: PhotoSaveOutcome) -> String {
        evaluateJSONCallback(name: "window.__clovery_imageSaveResult", payload: [outcome.rawValue])
    }

    static func photoDownloadResult(_ outcome: PhotoSaveOutcome) -> String {
        evaluateJSONCallback(name: "window.__cloveryPhotoDownloaded", payload: [outcome.rawValue])
    }

    static func photoSaved(filename: String) -> String {
        evaluateJSONCallback(name: "window.__cloveryPhotoSaved", payload: [filename])
    }

    static func photoLoaded(reqId: String, base64: String?) -> String {
        evaluateJSONCallback(
            name: "window.__cloveryPhotoLoaded",
            payload: [reqId, base64 ?? NSNull()]
        )
    }

    static func photoSaveFailed(filename: String, code: String) -> String {
        evaluateJSONCallback(
            name: "window.__cloveryPhotoSaveFailed",
            payload: [filename, code]
        )
    }

    static func iCloudData(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }

        return """
        (function(){
          const data = \(json);
          if (window.__clovery_applyICloud) {
            window.__clovery_applyICloud(data);
          } else {
            localStorage.setItem('clovery_icloud_pending', JSON.stringify(data));
          }
        })();
        """
    }

    static func vaultData(_ snapshot: VaultDiarySnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let entriesData = try? encoder.encode(snapshot.entries),
              let entries = try? JSONSerialization.jsonObject(with: entriesData) else {
            return ""
        }
        return evaluateJSONCallback(
            name: "window.__clovery_applyVault",
            payload: [[
                "entries": entries,
                "deleted_ids": snapshot.deletedIDs,
                "name": snapshot.name ?? NSNull()
            ]]
        )
    }

    /// Script that hands an entry written on the Apple Watch to the web app. Evaluates to `true` once
    /// the web app accepted it (or already had it), `false` while the page is not ready yet.
    static func addExternalEntry(_ entry: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return """
        (function(){
          const entry = \(json);
          if (typeof window.__clovery_addExternalEntry !== 'function') return false;
          return window.__clovery_addExternalEntry(entry) === true;
        })();
        """
    }

    static func restoreTrashEntry(_ entry: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return """
        (function(){
          const entry = \(json);
          if (window.__clovery_restoreTrashEntry) {
            window.__clovery_restoreTrashEntry(entry);
          }
        })();
        """
    }

    static func migrationExportResult(
        status: String,
        entryCount: Int = 0,
        photoCount: Int = 0,
        errorCode: String? = nil
    ) -> String {
        var result: [String: Any] = [
            "status": status,
            "entryCount": entryCount,
            "photoCount": photoCount,
        ]
        if let errorCode {
            result["errorCode"] = errorCode
        }
        return evaluateJSONCallback(
            name: "window.__cloveryMigrationExportResult",
            payload: [result]
        )
    }

    private static func evaluateJSONCallback(name: String, payload: [Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let json = String(data: data, encoding: .utf8),
              json.first == "[",
              json.last == "]" else {
            return "\(name)?.();"
        }

        return "\(name)?.(\(json.dropFirst().dropLast()));"
    }
}
