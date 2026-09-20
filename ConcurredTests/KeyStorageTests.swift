import XCTest
@testable import Concurred

@MainActor
final class KeyStorageTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredKeys-\(UUID())/keys.json")
    }

    func testLocalKeysRoundTripWithOwnerOnlyPermissions() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let local = LocalSecretStore(fileURL: url)
        XCTAssertNil(try local.value(for: "openrouter"))
        try local.set("first-key", for: "openrouter")
        try local.set("second-key", for: "featherless")
        XCTAssertEqual(try LocalSecretStore(fileURL: url).value(for: "openrouter"), "first-key")
        try local.set(nil, for: "openrouter")
        XCTAssertNil(try local.value(for: "openrouter"))
        XCTAssertEqual(try local.value(for: "featherless"), "second-key")
        let file = try FileManager.default.attributesOfItem(atPath: url.path)
        let folder = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testCorruptLocalKeysCannotBeOverwritten() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("broken keys".utf8)
        try original.write(to: url)
        let local = LocalSecretStore(fileURL: url)
        XCTAssertThrowsError(try local.value(for: "openrouter"))
        XCTAssertThrowsError(try local.set("new-key", for: "openrouter"))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testLocalModeNeverTouchesKeychainIncludingSaveAndClear() throws {
        let keychain = MemorySecrets()
        keychain.failWrites = true
        keychain.failReads = Set(Provider.all.map(\.id))
        let local = MemorySecrets()
        let store = AppStore(secrets: keychain, localSecrets: local, defaults: isolatedKeyDefaults())
        store.changeKeyStorage(to: .local)
        XCTAssertFalse(store.needsKeychainExplanation)
        for provider in Provider.all {
            store.loadKeyIfNeeded(for: provider)
            try store.setKey(" local-key ", for: provider)
            XCTAssertEqual(store.apiKey(for: provider), "local-key")
            try store.setKey(nil, for: provider)
        }
        XCTAssertTrue(keychain.reads.isEmpty)
        XCTAssertTrue(keychain.writes.isEmpty)
        XCTAssertEqual(local.reads.count, Provider.all.count)
    }

    func testSwitchingStorageClearsCacheWithoutCopyingOrDeletingKeys() throws {
        let keychain = MemorySecrets()
        let local = MemorySecrets()
        keychain.values[Provider.openrouter.id] = "protected-key"
        local.values[Provider.openrouter.id] = "local-key"
        let defaults = isolatedKeyDefaults()
        let store = AppStore(secrets: keychain, localSecrets: local, defaults: defaults)
        store.loadKeyIfNeeded(for: .openrouter)
        store.changeKeyStorage(to: .local)
        XCTAssertNil(store.apiKey(for: .openrouter))
        XCTAssertFalse(store.hasLoadedKey(for: .openrouter))
        XCTAssertTrue(local.reads.isEmpty, "Changing storage must not read keys itself")
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertEqual(store.apiKey(for: .openrouter), "local-key")
        XCTAssertEqual(AppStore(secrets: keychain, localSecrets: local, defaults: defaults).keyStorage, .local)
        store.changeKeyStorage(to: .keychain)
        XCTAssertNil(store.apiKey(for: .openrouter))
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertEqual(store.apiKey(for: .openrouter), "protected-key")
        XCTAssertTrue(keychain.writes.isEmpty)
        XCTAssertTrue(local.writes.isEmpty)
    }

    func testKeychainIsDefaultAndExplanationIsRemembered() {
        let defaults = isolatedKeyDefaults()
        let store = AppStore(secrets: MemorySecrets(), defaults: defaults)
        XCTAssertEqual(store.keyStorage, .keychain)
        XCTAssertTrue(store.needsKeychainExplanation)
        store.acknowledgeKeychainExplanation()
        XCTAssertFalse(AppStore(secrets: MemorySecrets(), defaults: defaults).needsKeychainExplanation)
    }

    func testCancelledExplanationDoesNotReadAndNeedsExplicitRetry() {
        let keychain = MemorySecrets()
        let store = AppStore(secrets: keychain, defaults: isolatedKeyDefaults())
        store.cancelKeyLoading(for: .openrouter)
        store.loadKeyIfNeeded(for: .openrouter)
        XCTAssertTrue(keychain.reads.isEmpty)
        XCTAssertNotNil(store.keyError(for: .openrouter))
        XCTAssertTrue(store.needsKeychainExplanation)
        store.acknowledgeKeychainExplanation()
        store.reloadKey(for: .openrouter)
        XCTAssertEqual(keychain.reads, [Provider.openrouter.id])
        XCTAssertNil(store.keyError(for: .openrouter))
    }

    func testFailedLocalWriteKeepsPreviousCachedKey() throws {
        let local = MemorySecrets()
        let store = AppStore(secrets: MemorySecrets(), localSecrets: local, defaults: isolatedKeyDefaults())
        store.changeKeyStorage(to: .local)
        try store.setKey("old-key", for: .openrouter)
        local.failWrites = true
        XCTAssertThrowsError(try store.setKey("replacement", for: .openrouter))
        XCTAssertEqual(store.apiKey(for: .openrouter), "old-key")
    }
}
