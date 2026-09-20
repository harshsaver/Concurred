import AppKit
import XCTest
@testable import Concurred

final class ConversationPortraitTests: XCTestCase {
    func testPortraitsRemainStableAfterConversationSaveAndReload() throws {
        let chat = Conversation(providerID: "openrouter", title: "Test", model: "test", messages: [], createdAt: Date(), updatedAt: Date())
        let original = ConversationPortrait.number(for: chat.id)
        var renamed = chat
        renamed.title = "Renamed"
        renamed.updatedAt = Date().addingTimeInterval(100)
        let reloaded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(renamed))
        XCTAssertEqual(ConversationPortrait.number(for: reloaded.id), original)
    }

    func testDistributionFavors20AndAboveWhileKeepingAllImagesEligible() {
        var counts: [Int: Int] = [:]
        for value in 0..<11000 {
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llX", UInt64(value)))!
            counts[ConversationPortrait.number(for: id), default: 0] += 1
        }
        XCTAssertEqual(Set(counts.keys), Set(10...44))
        let preferred = counts.filter { $0.key >= 20 }.values.reduce(0, +)
        XCTAssertGreaterThan(preferred, 9500)
        XCTAssertLessThan(preferred, 10500)
    }

    @MainActor
    func testEveryPortraitIsBundledAndDecodes() {
        for number in 10...44 {
            let image = NSImage(named: "Portrait\(number)")
            XCTAssertNotNil(image, "Missing portrait \(number)")
            XCTAssertEqual(image?.size, NSSize(width: 512, height: 512))
        }
    }
}
