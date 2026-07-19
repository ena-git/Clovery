import Foundation

struct APIErrorPayload: Decodable, Equatable {
    let code: String
    let message: String
}

enum APIError: Error, Equatable {
    case invalidConfiguration(String)
    case invalidResponse
    case emptyResponse
    case transport(String)
    case decoding(String)
    case server(code: String, message: String, statusCode: Int)

    var code: String? {
        guard case let .server(code, _, _) = self else {
            return nil
        }
        return code
    }

    var statusCode: Int? {
        guard case let .server(_, _, statusCode) = self else {
            return nil
        }
        return statusCode
    }
}
