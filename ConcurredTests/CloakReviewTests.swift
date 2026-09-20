import XCTest
@testable import Concurred

final class CloakReviewTests: XCTestCase {
    func testLocalEntitySuggestionsReferToExactSourceText() {
        let text = "The American Red Cross was established in Washington, D.C., by Clara Barton."
        let candidates = LocalIdentifierDetector.candidates(in: text)
        XCTAssertTrue(candidates.contains { $0.text == "Clara Barton" && $0.kind == "PERSON" })
        XCTAssertTrue(candidates.contains { $0.kind == "ORGANIZATION" })
        XCTAssertTrue(candidates.allSatisfy { text.contains($0.text) })
    }

    func testReviewHidesOnlySelectedValuesAndCanUndo() {
        let original = "Clara Barton has a 60% share in Example Org. Born on 1990-05-23."
        var review = CloakReview(original: [WireMessage(role: "user", content: original)], identity: .empty, vault: .init())
        XCTAssertEqual(review.outgoing.first?.content, original)
        let person = LocalIdentifierDetector.Candidate(text: "Clara Barton", kind: "PERSON")
        review.toggle(person)
        let masked = "[PERSON_1] has a 60% share in Example Org. Born on 1990-05-23."
        XCTAssertEqual(review.outgoing.first?.content, masked)
        XCTAssertEqual(Cloaker.uncloak(masked, vault: review.vault), original)
        XCTAssertFalse(review.needsReview("Clara Barton"))
        XCTAssertTrue(review.needsReview("Example Org"))
        review.toggle(person)
        XCTAssertEqual(review.outgoing.first?.content, original)
    }
}
