import XCTest
@testable import Concurred

final class AltIdentityStorageTests: XCTestCase {
    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredIdentityTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("alt-identity.json")
    }

    func testIdentitySavesLocallyWithOwnerOnlyPermissions() throws {
        let url = temporaryURL()
        XCTAssertEqual(try AltIdentity.load(from: url), .empty)
        var identity = AltIdentity()
        identity.realName = "Real Person"
        identity.altName = "Olivia Stone"
        identity.customPairs = [.init(real: "Other Person", alt: "Alex Bennett")]
        try identity.save(to: url)
        XCTAssertEqual(try AltIdentity.load(from: url), identity)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testInvalidIdentityDoesNotOverwriteTheSavedValues() throws {
        let url = temporaryURL()
        var saved = AltIdentity()
        saved.realName = "Real Person"
        saved.altName = "Olivia Stone"
        try saved.save(to: url)
        var invalid = saved
        invalid.altName = ""
        XCTAssertThrowsError(try invalid.save(to: url))
        XCTAssertEqual(try AltIdentity.load(from: url), saved)
    }

    func testCorruptLocalIdentityIsReportedWithoutResettingIt() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid identity".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try AltIdentity.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
