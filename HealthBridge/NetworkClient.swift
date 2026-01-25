import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func healthCheck(baseURL: String, apiKey: String) async throws -> Bool {
        guard let url = URL(string: baseURL)?.appendingPathComponent("healthz") else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (200..<300).contains(http.statusCode)
    }

    func send(endpoint: String, bodyData: Data, baseURL: String, apiKey: String) async throws {
        guard let base = URL(string: baseURL) else { throw NetworkError.invalidURL }
        let url = base.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = bodyData
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.serverError(status: http.statusCode)
        }
    }
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case serverError(status: Int)
}
