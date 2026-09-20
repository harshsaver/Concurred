import XCTest
@testable import Concurred

final class ServiceTests: XCTestCase {
    func testSSEFramingPreservesMultilineUTF8AndIgnoresComments() throws {
        var parser = ServerSentEvents()
        let input = "\u{FEFF}: heartbeat\r\ndata: {\r\ndata: \"value\": \"héllo 🌍\"}\r\n\r\nid: ignored\ndata: [DONE]\n\n"
        let events = try input.utf8.compactMap { try parser.append($0) }
        XCTAssertEqual(events, ["{\n\"value\": \"héllo 🌍\"}", "[DONE]"])
    }

    func testSSEOnlyDispatchesCompleteEventsAndHandlesBareCR() throws {
        var parser = ServerSentEvents()
        let events = try "data: first\r\rdata: unfinished".utf8.compactMap { try parser.append($0) }
        XCTAssertEqual(events, ["first"])
    }

    func testMalformedStreamEventIsNotSilentlyDropped() {
        XCTAssertThrowsError(try ChatClient.decodeEvent("not json"))
        XCTAssertThrowsError(try ChatClient.decodeEvent(#"{"error":{"message":"Model unavailable"}}"#)) { error in
            XCTAssertEqual(error.localizedDescription, "Model unavailable")
        }
        XCTAssertThrowsError(try ChatClient.decodeEvent(#"{"error":{"code":503}}"#))
    }

    func testStreamContentUsageAndFinishEvents() throws {
        let content = try ChatClient.decodeEvent(#"{"choices":[{"index":0,"delta":{"content":"hello"}}]}"#)
        XCTAssertEqual(content.content, "hello")
        XCTAssertFalse(content.finished)
        XCTAssertTrue(try ChatClient.decodeEvent(#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#).finished)
        XCTAssertNil(try ChatClient.decodeEvent(#"{"choices":[],"usage":{"total_tokens":10}}"#).content)
    }

    func testProxyRequiresValidHostAndPortWithoutDirectFallback() {
        var settings = NetworkSettings()
        settings.proxyEnabled = true
        XCTAssertThrowsError(try NetworkConfig.session(settings: settings))
        settings.proxyHost = "https://localhost"
        settings.proxyPort = 8080
        XCTAssertNotNil(settings.validationError)
        for host in ["localhost:0", "localhost?query", "localhost#fragment", "user@localhost"] {
            settings.proxyHost = host
            XCTAssertNotNil(settings.validationError, host)
        }
        settings.proxyHost = "127.0.0.1"
        settings.proxyPort = 65536
        XCTAssertNotNil(settings.validationError)
        settings.proxyPort = 9050
        XCTAssertNil(settings.validationError)
        settings.userAgent = "bad\r\nHeader: value"
        XCTAssertNotNil(settings.validationError)
    }

    func testSearchErrorsAndUnsafeSourcesAreExplicit() throws {
        XCTAssertThrowsError(try WebSearchService.decodeResults(Data(#"{"error":"Unauthorized"}"#.utf8)))
        XCTAssertThrowsError(try WebSearchService.decodeResults(Data(#"{"results":[]}"#.utf8)))
        let results = try WebSearchService.decodeResults(Data(#"{"results":[{"title":"Local","url":"file:///private/file"},{"title":"Source","url":"https://example.com","snippet":"Text"}]}"#.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url, "https://example.com")
    }

    func testMarkdownPreservesFenceContentsAndOrderedListStart() {
        let blocks = MarkdownParser.parse("````swift\nlet a = 1\n```\n````\n\n7. Seven\n8. Eight\n\n~~~\ncode\n~~~")
        XCTAssertEqual(blocks.count, 3)
        if case let .code(code, language) = blocks[0].kind {
            XCTAssertEqual(code, "let a = 1\n```")
            XCTAssertEqual(language, "swift")
        } else { XCTFail("Expected fenced code") }
        if case let .ordered(start, items) = blocks[1].kind {
            XCTAssertEqual(start, 7)
            XCTAssertEqual(items, ["Seven", "Eight"])
        } else { XCTFail("Expected ordered list") }
        if case let .code(code, _) = blocks[2].kind { XCTAssertEqual(code, "code") }
        else { XCTFail("Expected tilde fence") }
    }

    func testMarkdownDoesNotOfferLocalOrExecutableLinks() {
        let rendered = attributedMarkdown("[unsafe](file:///etc/passwd) [safe](https://example.com)")
        let links = rendered.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "https://example.com")!])
    }
}
