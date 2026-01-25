import XCTest
@testable import HealthBridge

final class NetworkClientTests: XCTestCase {
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
}
