import XCTest
@testable import Concurred

@MainActor
final class StoreTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredTests-\(UUID())/conversations.json")
    }

    func testConversationsRoundTripAndEmptyChatsAreNotWritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConversationStore(fileURL: url)
        var chat = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        chat.messages = [ChatMessage(role: .user, text: "Hello")]
        store.save(chat)
        _ = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        store.rename(chat.id, to: "  A title  ")
        let loaded = ConversationStore(fileURL: url)
        XCTAssertNil(loaded.errorText)
        XCTAssertEqual(loaded.conversations.count, 1)
        XCTAssertEqual(loaded.conversations.first?.title, "A title")
        XCTAssertEqual(loaded.conversations.first?.messages, chat.messages)
    }

    func testCorruptFileCannotBeOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid json".utf8)
        try original.write(to: url)
        let store = ConversationStore(fileURL: url)
        XCTAssertTrue(store.isReadBlocked)
        XCTAssertNotNil(store.errorText)
        var chat = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        chat.messages = [ChatMessage(role: .user, text: "Hello")]
        store.save(chat)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDeletedConversationCannotBeResurrectedByLateSave() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConversationStore(fileURL: url)
        var chat = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        store.delete(chat.id)
        chat.messages = [ChatMessage(role: .assistant, text: "late response")]
        store.save(chat)
        XCTAssertNil(store.conversation(chat.id))
    }

    func testWriteFailureIsVisibleAndCanBeRetried() throws {
        let url = temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(fileURL: url)
        try Data("obstacle".utf8).write(to: directory)
        var chat = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        chat.messages = [ChatMessage(role: .user, text: "Keep me")]
        store.save(chat)
        XCTAssertNotNil(store.errorText)
        try FileManager.default.removeItem(at: directory)
        store.retryPersistence()
        XCTAssertNil(store.errorText)
        XCTAssertEqual(ConversationStore(fileURL: url).conversations.first?.messages, chat.messages)
    }

    func testReuseFindsExistingEmptyChatEvenAfterAnotherChatIsUpdated() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConversationStore(fileURL: url)
        var first = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        first.messages = [ChatMessage(role: .user, text: "Hi")]
        store.save(first)
        let empty = store.newOrReuseEmpty(providerID: "openrouter", model: "model")
        first.updatedAt = .distantFuture
        store.save(first)
        XCTAssertEqual(store.newOrReuseEmpty(providerID: "openrouter", model: "model").id, empty.id)
    }

    func testKeyWritesTrimWhitespaceAndOnlyUpdateStateOnSuccess() throws {
        let secrets = MemorySecrets()
        let store = AppStore(secrets: secrets, defaults: isolatedKeyDefaults())
        try store.setKey("  first\n", for: .openrouter)
        XCTAssertEqual(store.apiKey(for: .openrouter), "first")
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertTrue(secrets.reads.isEmpty)
        secrets.failWrites = true
        XCTAssertThrowsError(try store.setKey("second", for: .openrouter))
        XCTAssertEqual(store.apiKey(for: .openrouter), "first")
        secrets.failWrites = false
        try store.setKey("   ", for: .openrouter)
        XCTAssertFalse(store.hasKey(for: .openrouter))
    }

    func testKeysLoadOnlyForRequestedProviderAndReuseCachedValue() {
        let secrets = MemorySecrets()
        secrets.values[Provider.openrouter.id] = "saved-key"
        let store = AppStore(secrets: secrets, defaults: isolatedKeyDefaults())
        XCTAssertTrue(secrets.reads.isEmpty, "Launching the app must not request Keychain access")
        XCTAssertFalse(store.hasLoadedKey(for: .openrouter))

        store.loadKeyIfNeeded(for: .openrouter)
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertEqual(store.apiKey(for: .openrouter), "saved-key")
        XCTAssertEqual(secrets.reads, [Provider.openrouter.id])
        XCTAssertFalse(store.hasLoadedKey(for: .featherless))

        store.loadKeyIfNeeded(for: .featherless)
        store.loadKeyIfNeeded(for: .featherless)
        XCTAssertTrue(store.hasLoadedKey(for: .featherless))
        XCTAssertFalse(store.hasKey(for: .featherless))
        XCTAssertEqual(secrets.reads, [Provider.openrouter.id, Provider.featherless.id])
    }

    func testDeniedKeyReadRequiresExplicitRetryAndPreservesCachedKey() {
        let secrets = MemorySecrets()
        secrets.values[Provider.openrouter.id] = "saved-key"
        secrets.failReads.insert(Provider.openrouter.id)
        let store = AppStore(secrets: secrets, defaults: isolatedKeyDefaults())
        store.loadKeyIfNeeded(for: .openrouter)
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertEqual(secrets.reads.count, 1)
        XCTAssertNotNil(store.keyError(for: .openrouter))
        XCTAssertFalse(store.hasKey(for: .openrouter))

        secrets.failReads.remove(Provider.openrouter.id)
        store.reloadKey(for: .openrouter)
        XCTAssertEqual(secrets.reads.count, 2)
        XCTAssertNil(store.keyError(for: .openrouter))
        XCTAssertEqual(store.apiKey(for: .openrouter), "saved-key")

        secrets.failReads.insert(Provider.openrouter.id)
        store.reloadKey(for: .openrouter)
        XCTAssertNotNil(store.keyError(for: .openrouter))
        XCTAssertEqual(store.apiKey(for: .openrouter), "saved-key")
    }
}

final class MemorySecrets: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    var failWrites = false
    var reads: [String] = []
    var writes: [String] = []
    var failReads: Set<String> = []
    func value(for key: String) throws -> String? {
        reads.append(key)
        if failReads.contains(key) { throw CocoaError(.fileReadNoPermission) }
        return values[key]
    }
    func set(_ value: String?, for key: String) throws {
        writes.append(key)
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        values[key] = value
    }
}

func isolatedKeyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ConcurredTests-\(UUID().uuidString)")!
}
