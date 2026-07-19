import Foundation

struct APIRequest {
    let method: String
    let path: String
    let body: Data?
    let bearerToken: String?

    init(
        method: String,
        path: String,
        body: Data? = nil,
        bearerToken: String? = nil
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.bearerToken = bearerToken
    }
}
