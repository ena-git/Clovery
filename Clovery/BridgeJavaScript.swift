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
              let data = try? JSONSerialization.data(withJSONObject: payload),
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
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8),
              json.first == "[",
              json.last == "]" else {
            return "\(name)?.();"
        }

        return "\(name)?.(\(json.dropFirst().dropLast()));"
    }
}
