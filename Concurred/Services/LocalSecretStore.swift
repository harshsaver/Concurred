import Foundation

enum KeyStorageMode: String, CaseIterable, Identifiable {
    case keychain
    case local

    var id: String { rawValue }
    var title: String { self == .keychain ? "macOS Keychain" : "Local file (no Keychain prompts)" }
}

/// Explicitly chosen, unencrypted key storage. Never reads or imports Keychain items.
struct LocalSecretStore: SecretStore {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("dev.october.concord/provider-keys.json")) {
        self.fileURL = fileURL
    }

    func value(for key: String) throws -> String? {
        try read()[key]
    }

    func set(_ value: String?, for key: String) throws {
        // Read first: an unreadable file must never be replaced with an empty store.
        var keys = try read()
        keys[key] = value?.isEmpty == false ? value : nil
        let data = try JSONEncoder().encode(keys)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func read() throws -> [String: String] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}
