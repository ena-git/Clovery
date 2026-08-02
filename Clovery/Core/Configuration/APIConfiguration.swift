import Foundation

struct APIConfiguration: Equatable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> APIConfiguration {
        let configuredURL = bundle.object(forInfoDictionaryKey: "CloveryAPIBaseURL") as? String
        let environmentURL = environment["CLOVERY_API_BASE_URL"]
        let rawURL = (environmentURL ?? configuredURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL), url.scheme != nil, url.host != nil else {
            throw APIError.invalidConfiguration("Clovery API base URL is missing or invalid.")
        }
        return APIConfiguration(baseURL: url)
    }

    func validate(for configuration: BuildConfiguration) throws {
        guard baseURL.scheme?.lowercased() == "https" || configuration == .debug else {
            throw APIError.invalidConfiguration("Release authentication requires HTTPS.")
        }
        if configuration == .release, baseURL.host?.contains("staging.") == true {
            throw APIError.invalidConfiguration("Release authentication cannot use the staging API.")
        }
    }
}

enum BuildConfiguration: Equatable {
    case debug
    case release
}
