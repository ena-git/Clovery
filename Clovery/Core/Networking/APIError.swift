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

    var isTerminalAuthenticationRejection: Bool {
        statusCode == 401 || code == "invalid_refresh_token"
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Clovery 服务配置无效。"
        case .invalidResponse, .emptyResponse, .decoding:
            return "Clovery 服务响应无效。"
        case .transport:
            return "暂时无法连接 Clovery 服务。"
        case .server:
            return "Clovery 服务请求失败。"
        }
    }
}
