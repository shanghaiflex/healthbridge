import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func healthCheck(baseURL: String) async throws -> Bool {
        guard let base = normalizedBaseURL(from: baseURL) else {
            throw NetworkError.invalidURL
        }
        let url = base.appendingPathComponent("healthz")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (200..<300).contains(http.statusCode)
    }

    func send(endpoint: String, bodyData: Data, baseURL: String) async throws {
        guard let base = normalizedBaseURL(from: baseURL) else { throw NetworkError.invalidURL }
        let url = base.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            Logger.shared.error("HTTP \(http.statusCode) POST \(url.absoluteString) failed. Payload bytes: \(bodyData.count). Response: \(message ?? "<empty>")")
            throw NetworkError.serverError(status: http.statusCode, url: url.absoluteString, message: message)
        }
    }

    private func normalizedBaseURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "http://\(trimmed)")
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard var string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if string.count > 500 {
            let index = string.index(string.startIndex, offsetBy: 500)
            string = String(string[string.startIndex..<index]) + "…"
        }
        return string
    }
}

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(status: Int, url: String, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Server URL is invalid. Include http:// or https:// and try again."
        case .invalidResponse:
            return "Server response was missing or malformed."
        case .serverError(let status, let url, let message):
            var description = "Server responded with HTTP status \(status) for \(url)."
            if let message {
                description += " Message: \(message)"
            }
            return description
        }
    }
}
