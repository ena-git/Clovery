import Foundation

struct APIRequest {
    let method: String
    let path: String
    let body: Data?
    let bearerToken: String?
    let stableRequestID: String?

    init(
        method: String,
        path: String,
        body: Data? = nil,
        bearerToken: String? = nil,
        stableRequestID: String? = nil
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.bearerToken = bearerToken
        self.stableRequestID = stableRequestID
    }

    func authenticated(with accessToken: String) -> APIRequest {
        APIRequest(
            method: method,
            path: path,
            body: body,
            bearerToken: accessToken,
            stableRequestID: stableRequestID
        )
    }

    var allowsAuthenticationRetry: Bool {
        switch method.uppercased() {
        case "GET", "HEAD", "OPTIONS", "PUT", "DELETE":
            return true
        default:
            return !(stableRequestID?.isEmpty ?? true)
        }
    }
}
