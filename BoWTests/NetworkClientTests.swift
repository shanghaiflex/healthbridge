import XCTest
@testable import BoW

final class NetworkClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStub.requestHandler = nil
    }

    func testSendUsesPostMethod() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let payload = Data("{}".utf8)
        try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "http://localhost:8080")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendAllowsBaseURLWithoutScheme() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.10:8080/v1/ingest/health/workouts")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let payload = Data("{}".utf8)
        try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "192.168.1.10:8080")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendTrimsHealthzPathFromBaseURL() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.bodywithoutorgans.cc/v1/ingest/health/workouts")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let payload = Data("{}".utf8)
        try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "https://api.bodywithoutorgans.cc/healthz")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendAddsAuthorizationHeaderWhenTokenProvided() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let payload = Data("{}".utf8)
        try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "https://example.com", authToken: "test-token")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendPropagatesServerErrorMessage() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("boom".utf8))
        }

        let payload = Data("{}".utf8)
        do {
            try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "http://example.com")
            XCTFail("Expected to throw")
        } catch let error as NetworkError {
            switch error {
            case .serverError(let status, let url, let message):
                XCTAssertEqual(status, 500)
                XCTAssertEqual(url, "http://example.com/v1/ingest/health/workouts")
                XCTAssertEqual(message, "boom")
            default:
                XCTFail("Unexpected NetworkError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testHealthCheckAddsAuthorizationHeaderWhenTokenProvided() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        let expectation = XCTestExpectation(description: "Request handled")
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/healthz")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        _ = try await client.healthCheck(baseURL: "https://example.com", authToken: "test-token")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendRetriesTransientNetworkConnectionLoss() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = NetworkClient(session: session)

        var attempts = 0
        let expectation = XCTestExpectation(description: "Request eventually succeeds")
        URLProtocolStub.requestHandler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.networkConnectionLost)
            }
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let payload = Data("{}".utf8)
        try await client.send(endpoint: "v1/ingest/health/workouts", bodyData: payload, baseURL: "https://example.com")
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(attempts, 2)
    }
}
