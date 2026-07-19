import Foundation

final class APIClient {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        decoding responseType: Response.Type
    ) async throws -> Response {
        let data = try await perform(request)
        guard !data.isEmpty else {
            throw APIError.emptyResponse
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func sendWithoutResponse(_ request: APIRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: APIRequest) async throws -> Data {
        let urlRequest = try makeURLRequest(request)
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeServerError(data: data, statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func makeURLRequest(_ request: APIRequest) throws -> URLRequest {
        let normalizedPath = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = configuration.baseURL.appendingPathComponent(normalizedPath)
        guard url.scheme != nil, url.host != nil else {
            throw APIError.invalidConfiguration("Clovery API request URL is invalid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil {
            urlRequest.httpBody = request.body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken = request.bearerToken, !bearerToken.isEmpty {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    private func makeServerError(data: Data, statusCode: Int) -> APIError {
        if let payload = try? decoder.decode(APIErrorPayload.self, from: data) {
            return .server(code: payload.code, message: payload.message, statusCode: statusCode)
        }
        return .server(code: "http_\(statusCode)", message: "The service could not complete the request.", statusCode: statusCode)
    }
}
