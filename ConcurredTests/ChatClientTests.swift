import XCTest
@testable import Concurred

final class ChatClientTests: XCTestCase {
    private func client(status: Int = 200, type: String = "text/event-stream", body: String,
                        inspect: @escaping @Sendable (URLRequest) -> Void = { _ in }) -> ChatClient {
        StubURLProtocol.setHandler { request in
            inspect(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
            return (response, Data(body.utf8))
        }
        return ChatClient(baseURL: URL(string: "https://provider.test/v1")!, apiKey: "test-secret", makeSession: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            return URLSession(configuration: configuration)
        })
    }

    func testStreamingRequestAndUTF8Response() async throws {
        let client = client(body: "data: {\"choices\":[{\"delta\":{\"content\":\"Hello 🌍\"}}]}\n\ndata: [DONE]\n\n") { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        }
        var response = ""
        for try await delta in client.chatStream(model: "test-model", messages: [WireMessage(role: "user", content: "Hi")]) {
            response += delta
        }
        XCTAssertEqual(response, "Hello 🌍")
    }

    func testTruncatedResponseThrowsAfterDeliveringPartialText() async {
        let client = client(body: "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")
        var response = ""
        do {
            for try await delta in client.chatStream(model: "test-model", messages: []) { response += delta }
            XCTFail("A disconnected stream must not look complete")
        } catch {
            XCTAssertEqual(response, "partial")
            XCTAssertEqual(error.localizedDescription, ChatClient.ClientError.interrupted.localizedDescription)
        }
    }

    func testHTTPAuthenticationErrorIsActionable() async {
        let client = client(status: 401, type: "application/json", body: #"{"error":{"message":"secret server details"}}"#)
        do {
            for try await _ in client.chatStream(model: "test-model", messages: []) {}
            XCTFail("Expected authentication failure")
        } catch { XCTAssertEqual(error.localizedDescription, "Invalid or missing API key. Check it in Settings.") }
    }

    func testJSONInsteadOfSSEIsRejected() async {
        let client = client(type: "application/json", body: #"{"choices":[]}"#)
        do {
            for try await _ in client.chatStream(model: "test-model", messages: []) {}
            XCTFail("Expected protocol error")
        } catch { XCTAssertEqual(error.localizedDescription, ChatClient.ClientError.invalidResponse.localizedDescription) }
    }

    func testLiveCatalogIsSortedUniqueAndContainsNoEmptyIDs() async throws {
        let client = client(type: "application/json", body: #"{"data":[{"id":"z"},{"id":"a"},{"id":"z"},{"id":" "}]}"#) { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
        }
        let models = try await client.listModels()
        XCTAssertEqual(models, ["a", "z"])
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?
    static func setHandler(_ value: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.withLock { handler = value }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.lock.withLock({ Self.handler }) else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
