import XCTest
@testable import Concurred

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func makeVM(client: StubChatClient,
                        search: @escaping @Sendable (String) async throws -> [WebSearchResult] = { _ in [] },
                        identity: AltIdentity = .empty) -> (ChatViewModel, ConversationStore) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredTests-\(UUID())/chats.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConversationStore(fileURL: url)
        let chat = store.newOrReuseEmpty(providerID: "openrouter", model: "test-model")
        return (ChatViewModel(provider: .openrouter, apiKey: "test-key", conversationID: chat.id, store: store,
                              client: client, search: search, loadIdentity: { identity }), store)
    }

    private func eventually(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testStopThenSendCannotBeMutatedByTheOldResponse() async throws {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client)
        vm.input = "First question"
        vm.send()
        try await eventually { client.requestCount == 1 }
        client.yield("partial", request: 0)
        try await Task.sleep(for: .milliseconds(60))
        vm.stop()
        XCTAssertFalse(vm.isStreaming)
        XCTAssertEqual(vm.messages.last?.text, "partial")
        vm.input = "Second question"
        vm.send()
        try await eventually { client.requestCount == 2 }
        client.yield("late old delta", request: 0)
        client.finish(request: 0)
        client.yield("new reply", request: 1)
        client.finish(request: 1)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.map(\.text), ["First question", "partial", "Second question", "new reply"])
        XCTAssertNil(vm.errorText)
    }

    func testRetryDoesNotDuplicateUserQuestionAndReplacesLastReply() async throws {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client)
        vm.input = "Question"
        vm.send()
        try await eventually { client.requestCount == 1 }
        client.yield("first reply", request: 0)
        client.finish(request: 0)
        try await eventually { !vm.isStreaming }
        vm.input = "Unsent draft"
        vm.retry()
        try await eventually { client.requestCount == 2 }
        XCTAssertEqual(client.messages(request: 1).map(\.content), ["Question"])
        client.yield("replacement reply", request: 1)
        client.finish(request: 1)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.map(\.text), ["Question", "replacement reply"])
        XCTAssertEqual(vm.input, "Unsent draft")
    }

    func testDeletedActiveConversationStaysDeletedWhenResponseFinishes() async throws {
        let client = StubChatClient()
        let (vm, store) = makeVM(client: client)
        vm.input = "Question"
        vm.send()
        try await eventually { client.requestCount == 1 }
        store.delete(vm.conversationID)
        client.yield("late response", request: 0)
        client.finish(request: 0)
        try await eventually { !vm.isStreaming }
        XCTAssertTrue(store.conversations.isEmpty)
    }

    func testCloakAppliesBeforeSearchAndProviderRequests() async throws {
        let client = StubChatClient()
        var identity = AltIdentity()
        identity.realName = "Alice Example"
        identity.altName = "Olivia Stone"
        let searched = expectation(description: "Cloaked search")
        let (vm, _) = makeVM(client: client, search: { query in
            XCTAssertEqual(query, "Find Alice Example".replacingOccurrences(of: "Alice Example", with: "Olivia Stone"))
            searched.fulfill()
            return [WebSearchResult(title: "Example", url: "https://example.com", snippet: "Some source")]
        }, identity: identity)
        vm.cloak = true
        vm.groundWithSearch = true
        vm.input = "Find Alice Example"
        vm.send()
        await fulfillment(of: [searched], timeout: 2)
        try await eventually { client.requestCount == 1 }
        XCTAssertFalse(client.messages(request: 0).contains { $0.content.contains("Alice Example") })
        client.yield("Hello Olivia ", request: 0)
        client.yield("Stone", request: 0)
        client.finish(request: 0)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.text, "Hello Alice Example")
    }

    func testSearchFailurePreventsUngroundedProviderRequest() async throws {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client, search: { _ in throw WebSearchService.SearchError.failed })
        vm.groundWithSearch = true
        vm.input = "Question"
        vm.send()
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertNotNil(vm.errorText)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.canRetry)
    }

    func testFirstNameReplyIsRestoredDuringStreamingAndPersisted() async throws {
        let client = StubChatClient()
        var identity = AltIdentity()
        identity.realName = "Harsh"
        identity.altName = "Chloe Stone"
        let (vm, store) = makeVM(client: client, identity: identity)
        vm.cloak = true
        vm.input = "hi i am Harsh, who are you"
        vm.send()
        try await eventually { client.requestCount == 1 }
        XCTAssertEqual(client.messages(request: 0).last?.content, "hi i am Chloe Stone, who are you")

        try await Task.sleep(for: .milliseconds(60))
        client.yield("Hi Chlo", request: 0)
        try await eventually { vm.messages.last?.text == "Hi " }
        try await Task.sleep(for: .milliseconds(60))
        client.yield("e! I'm an AI assistant.", request: 0)
        try await eventually { vm.messages.last?.text == "Hi Harsh! I'm an AI assistant." }
        client.finish(request: 0)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(store.conversation(vm.conversationID)?.messages.last?.text, "Hi Harsh! I'm an AI assistant.")

        vm.input = "What did I say my name was?"
        vm.send()
        try await eventually { client.requestCount == 2 }
        XCTAssertFalse(client.messages(request: 1).contains { $0.content.contains("Harsh") })
        client.yield("Chloe Stone", request: 1)
        client.finish(request: 1)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.text, "Harsh")
    }

    func testCloakChoiceIsCapturedForReplyAndOffMeansNoSubstitutions() async throws {
        let client = StubChatClient()
        var identity = AltIdentity()
        identity.realName = "Harsh"
        identity.altName = "Chloe Stone"
        let (vm, _) = makeVM(client: client, identity: identity)
        vm.cloak = true
        vm.input = "I am Harsh"
        vm.send()
        try await eventually { client.requestCount == 1 }
        vm.cloak = false
        try await Task.sleep(for: .milliseconds(60))
        client.yield("Hi Chloe", request: 0)
        try await eventually { vm.messages.last?.text == "Hi " }
        vm.stop()
        // Stop also flushes a complete name held at the end of a partial reply.
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.text, "Hi Harsh")

        vm.input = "Harsh says hello"
        vm.send()
        try await eventually { client.requestCount == 2 }
        XCTAssertEqual(client.messages(request: 1).last?.content, "Harsh says hello")
        client.yield("Hi Chloe!", request: 1)
        client.finish(request: 1)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.text, "Hi Chloe!")
    }

    func testStopDuringSearchPreventsLaterProviderRequest() async throws {
        let client = StubChatClient()
        let search = SuspendedSearch()
        let (vm, _) = makeVM(client: client, search: { query in try await search.search(query) })
        vm.groundWithSearch = true
        vm.input = "Question"
        vm.send()
        try await eventually { search.hasStarted }
        vm.stop()
        search.complete()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertFalse(vm.isStreaming)
        XCTAssertNil(vm.errorText)
    }

    func testAPIKeyChangeCancelsCurrentRequestWithoutLosingDraft() async throws {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client)
        vm.input = "Question"
        vm.send()
        try await eventually { client.requestCount == 1 }
        vm.input = "Next question draft"
        vm.updateAPIKey("replacement-test-key")
        XCTAssertFalse(vm.isStreaming)
        XCTAssertEqual(vm.input, "Next question draft")
        client.finish(request: 0)
        XCTAssertNil(vm.errorText)
    }

    func testNoEmptyAssistantPlaceholderIsPersisted() async throws {
        let client = StubChatClient()
        let (vm, store) = makeVM(client: client)
        vm.input = "Question"
        vm.send()
        XCTAssertEqual(store.conversation(vm.conversationID)?.messages.map(\.role), [.user])
        vm.stop()
        XCTAssertEqual(vm.messages.map(\.role), [.user])
        XCTAssertNil(vm.errorText)
    }

    func testDraftSurvivesReopeningConversationAndClearsOnSend() {
        let client = StubChatClient()
        let (vm, store) = makeVM(client: client)
        vm.input = "Unsent text"
        let reopened = ChatViewModel(provider: .openrouter, apiKey: "test-key", conversationID: vm.conversationID, store: store, client: client)
        XCTAssertEqual(reopened.input, "Unsent text")
        reopened.send()
        XCTAssertEqual(store.draft(for: vm.conversationID), "")
        reopened.stop()
    }

    func testEmptyCatalogHasVisibleErrorAndCustomModelWorks() async {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client)
        await vm.loadModels()
        XCTAssertNotNil(vm.modelsError)
        vm.selectModel("  custom/model  ")
        vm.input = "Hello"
        XCTAssertEqual(vm.selectedModel, "custom/model")
        XCTAssertTrue(vm.canSend)
    }

    func testReviewedTextIsExactlyWhatSearchAndProviderReceive() async throws {
        let client = StubChatClient()
        let searched = expectation(description: "Reviewed search")
        let (vm, _) = makeVM(client: client, search: { query in
            XCTAssertEqual(query, "[PERSON_1] owns 60%")
            searched.fulfill()
            return [WebSearchResult(title: "Result", url: "https://example.org", snippet: "Clara Barton")]
        })
        vm.cloak = true
        vm.groundWithSearch = true
        vm.input = "Clara Barton owns 60%"
        var review = try vm.makeCloakReview()
        review.toggle(.init(text: "Clara Barton", kind: "PERSON"))
        XCTAssertEqual(client.requestCount, 0)
        vm.send(review: review)
        await fulfillment(of: [searched], timeout: 2)
        try await eventually { client.requestCount == 1 }
        XCTAssertEqual(client.messages(request: 0).last?.content, review.outgoing.last?.content)
        XCTAssertFalse(client.messages(request: 0).contains { $0.content.contains("Clara Barton") })
        client.yield("[PERSON_1] owns 60%", request: 0)
        client.finish(request: 0)
        try await eventually { !vm.isStreaming }
        XCTAssertEqual(vm.messages.last?.text, "Clara Barton owns 60%")
        vm.groundWithSearch = false
        vm.retry()
        try await eventually { client.requestCount == 2 }
        XCTAssertEqual(client.messages(request: 1).last?.content, "[PERSON_1] owns 60%")
        vm.stop()
    }

    func testCancelledOrStaleReviewDoesNotChangeDraftOrSend() throws {
        let client = StubChatClient()
        let (vm, _) = makeVM(client: client)
        vm.cloak = true
        vm.input = "Clara Barton"
        var review = try vm.makeCloakReview()
        review.toggle(.init(text: "Clara Barton", kind: "PERSON"))
        let fresh = try vm.makeCloakReview()
        XCTAssertEqual(fresh.outgoing.last?.content, "Clara Barton")
        XCTAssertEqual(vm.input, "Clara Barton")
        vm.input = "Changed draft"
        vm.send(review: review)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertEqual(vm.input, "Changed draft")
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNotNil(vm.errorText)
    }
}

private final class StubChatClient: ChatServing, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [([WireMessage], AsyncThrowingStream<String, Error>.Continuation)] = []
    var requestCount: Int { lock.withLock { requests.count } }
    func messages(request: Int) -> [WireMessage] { lock.withLock { requests[request].0 } }
    func listModels() async throws -> [String] { [] }
    func chatStream(model: String, messages: [WireMessage]) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        lock.withLock { requests.append((messages, continuation)) }
        return stream
    }
    func yield(_ text: String, request: Int) { _ = lock.withLock { requests[request].1 }.yield(text) }
    func finish(request: Int) { lock.withLock { requests[request].1 }.finish() }
}

private final class SuspendedSearch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[WebSearchResult], Error>?
    var hasStarted: Bool { lock.withLock { continuation != nil } }
    func search(_ query: String) async throws -> [WebSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }
    func complete() {
        lock.withLock { continuation }?.resume(returning: [WebSearchResult(title: "Source", url: "https://example.com", snippet: "text")])
    }
}
