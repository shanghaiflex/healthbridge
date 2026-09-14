import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession
    private let useInjectedSession: Bool
    private let retryDelaysNanoseconds: [UInt64] = [300_000_000, 1_000_000_000, 2_000_000_000]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.useInjectedSession = true
        } else {
            self.session = NetworkClient.makeDefaultSession()
            self.useInjectedSession = false
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }

    private static func makeRetrySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }

    func healthCheck(baseURL: String, authToken: String? = nil) async throws -> Bool {
        guard let base = normalizedBaseURL(from: baseURL) else {
            throw NetworkError.invalidURL
        }
        let url = base.appendingPathComponent("healthz")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthorizationHeader(to: &request, authToken: authToken)
        let (_, response) = try await performData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (200..<300).contains(http.statusCode)
    }

    func send(endpoint: String, bodyData: Data, baseURL: String, authToken: String? = nil, trigger: String? = nil) async throws {
        guard let base = normalizedBaseURL(from: baseURL) else { throw NetworkError.invalidURL }
        let url = base.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The server logs this next to every batch: the proof of whether background wake-ups happen.
        if let trigger { request.setValue(trigger, forHTTPHeaderField: "X-Trigger") }
        addAuthorizationHeader(to: &request, authToken: authToken)
        request.httpBody = bodyData
        let (data, response) = try await performData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            Logger.shared.error("HTTP \(http.statusCode) POST \(url.absoluteString) failed. Payload bytes: \(bodyData.count). Response: \(message ?? "<empty>")")
            throw NetworkError.serverError(status: http.statusCode, url: url.absoluteString, message: message)
        }
    }

    /// Absolute URL for a server path such as `/audio/x.m4a` (used by the background download session).
    func absoluteURL(path: String, baseURL: String) -> URL? {
        guard let base = normalizedBaseURL(from: baseURL) else { return nil }
        return base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    /// Small JSON GET for the site API (`api/lectures/preload`). Fails fast when offline instead of waiting
    /// for connectivity: the lectures screen must come up from its cache in the metro, not hang.
    func get(path: String, baseURL: String, authToken: String?) async throws -> Data {
        guard let url = absoluteURL(path: path, baseURL: baseURL) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthorizationHeader(to: &request, authToken: authToken)
        return try await performQuick(request)
    }

    func patch(path: String, json: [String: Any], baseURL: String, authToken: String?) async throws -> Data {
        guard let url = absoluteURL(path: path, baseURL: baseURL) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorizationHeader(to: &request, authToken: authToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await performQuick(request)
    }

    private static let quickSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private func performQuick(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await (useInjectedSession ? session : Self.quickSession).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.serverError(status: http.statusCode, url: request.url?.absoluteString ?? "", message: errorMessage(from: data))
        }
        return data
    }

    private func normalizedBaseURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsedURL: URL?
        if let url = URL(string: trimmed), url.scheme != nil {
            parsedURL = url
        } else {
            parsedURL = URL(string: "http://\(trimmed)")
        }
        guard var components = parsedURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "healthz" {
            components.path = ""
        }
        return components.url
    }

    private func addAuthorizationHeader(to request: inout URLRequest, authToken: String?) {
        guard let token = authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func performData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...retryDelaysNanoseconds.count {
            do {
                var request = request
                request.timeoutInterval = 90
                request.setValue("close", forHTTPHeaderField: "Connection")

                let activeSession = useInjectedSession ? session : Self.makeRetrySession()

                let result = try await activeSession.data(for: request)
                if !useInjectedSession {
                    activeSession.finishTasksAndInvalidate()
                }
                return result
            } catch {
                guard shouldRetry(error), attempt < retryDelaysNanoseconds.count else {
                    throw error
                }
                lastError = error
                let urlText = request.url?.absoluteString ?? "<unknown>"
                Logger.shared.error("Transient network failure on \(urlText), retry \(attempt + 1)/\(retryDelaysNanoseconds.count). Error: \(error)")
                try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
            }
        }
        throw lastError ?? NetworkError.invalidResponse
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
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
