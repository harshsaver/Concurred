import XCTest
@testable import Concurred

final class CloakerTests: XCTestCase {
    private func nameIdentity(real: String = "Harsh", alt: String = "Chloe Stone") -> AltIdentity {
        var identity = AltIdentity()
        identity.realName = real
        identity.altName = alt
        return identity
    }

    func testFullAndFirstNameRepliesRestoreSingleRealName() {
        let identity = nameIdentity()
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("hi i am Harsh, who are you", identity: identity, vault: &vault),
                       "hi i am Chloe Stone, who are you")
        for (reply, expected) in [
            ("Hi Chloe! I'm an AI assistant.", "Hi Harsh! I'm an AI assistant."),
            ("Hi Chloe Stone!", "Hi Harsh!"),
            ("CHLOE, here's your answer.", "Harsh, here's your answer."),
            ("chloe's notes and Chloe Stone’s plan", "Harsh's notes and Harsh’s plan"),
            ("Hi Chloe\n  Stone!", "Hi Harsh!")
        ] {
            XCTAssertEqual(Cloaker.uncloak(reply, vault: vault), expected)
        }
    }

    func testGivenNameInputIsCloakedWhenFullRealNameIsConfigured() {
        let identity = nameIdentity(real: "Harsh Mehta")
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("I'm Harsh. My name is Harsh Mehta.", identity: identity, vault: &vault),
                       "I'm Chloe. My name is Chloe Stone.")
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe! Hello Chloe Stone.", vault: vault), "Hi Harsh! Hello Harsh Mehta.")
    }

    func testNameVariantsDoNotAlterWordsIdentifiersEmailsOrURLs() {
        let identity = nameIdentity()
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Harsh", identity: identity, vault: &vault)
        let untouched = "Chloette, myChloe, Chloe2, Chloe_Stone, chloe@example.com, https://example.com/Chloe and Stone buildings."
        XCTAssertEqual(Cloaker.uncloak(untouched, vault: vault), untouched)
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe!", vault: Cloaker.Vault()), "Hi Chloe!")
    }

    func testNameInsideEmailUsesTheEmailMappingWithoutLeakingName() {
        let identity = nameIdentity()
        var vault = Cloaker.Vault()
        let original = "Harsh can be reached at harsh@example.com"
        let masked = Cloaker.cloak(original, identity: identity, vault: &vault)
        XCTAssertFalse(masked.lowercased().contains("harsh"))
        XCTAssertTrue(masked.hasPrefix("Chloe Stone can be reached at [EMAIL_"))
        XCTAssertEqual(Cloaker.uncloak(masked, vault: vault), original)
    }

    func testNamesInLinksAreMaskedAsWholeURLsAndRestoreWithoutBreakingMarkdown() {
        let identity = nameIdentity()
        var vault = Cloaker.Vault()
        let original = "Harsh shared [a profile](https://example.org/Harsh) and https://example.net/?name=Harsh."
        let masked = Cloaker.cloak(original, identity: identity, vault: &vault)
        XCTAssertFalse(masked.lowercased().contains("harsh"))
        XCTAssertTrue(masked.hasPrefix("Chloe Stone shared [a profile](https://example.com/"))
        XCTAssertEqual(Cloaker.uncloak(masked, vault: vault), original)
        XCTAssertEqual(Cloaker.cloak(original, identity: identity, vault: &vault), masked)
    }

    func testAmbiguousFirstNameIsNotRestoredToTheWrongPerson() {
        var identity = nameIdentity()
        identity.customPairs = [.init(real: "Priya", alt: "Chloe")]
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Harsh and Priya", identity: identity, vault: &vault)
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe. Hello Chloe Stone.", vault: vault), "Hi Chloe. Hello Harsh.")
    }

    func testExplicitPairsOverrideInferredFirstNamesBeforeSending() {
        var identity = nameIdentity(real: "Harsh Mehta")
        identity.customPairs = [.init(real: "Harsh", alt: "Alex")]
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("Harsh and Harsh Mehta", identity: identity, vault: &vault), "Alex and Chloe Stone")
        XCTAssertEqual(Cloaker.uncloak("Alex and Chloe Stone", vault: vault), "Harsh and Harsh Mehta")
    }

    func testFirstNameRestorationStaysStableAfterIdentityEdit() {
        var identity = nameIdentity()
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Harsh", identity: identity, vault: &vault)
        identity.altName = "Olivia Bennett"
        XCTAssertEqual(Cloaker.cloak("Harsh", identity: identity, vault: &vault), "Chloe Stone")
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe!", vault: vault), "Hi Harsh!")
        XCTAssertEqual(Cloaker.uncloak("Hi Olivia!", vault: vault), "Hi Olivia!")
    }

    func testStreamingHoldsIncompleteAliasesAtEveryCharacterBoundary() {
        let identity = nameIdentity()
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Harsh", identity: identity, vault: &vault)
        for reply in ["Hi Chloe!", "Hi Chloe Stone!", "Hi CHLOE   STONE!"] {
            let final = "Hi Harsh!"
            for count in 0...reply.count {
                let rendered = Cloaker.uncloak(String(reply.prefix(count)), vault: vault, isStreaming: true)
                XCTAssertTrue(final.hasPrefix(rendered), "Alias fragment displayed: \(rendered)")
            }
            XCTAssertEqual(Cloaker.uncloak(reply, vault: vault), final)
        }
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe can help.", vault: vault, isStreaming: true), "Hi Harsh can help.")
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe", vault: vault), "Hi Harsh")
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe Stone", vault: vault), "Hi Harsh")
    }

    func testCompoundNamesAndTypographicApostrophes() {
        let identity = nameIdentity(real: "Anne-Marie O'Neil", alt: "Chloe O’Connor")
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("Anne-Marie O’Neil", identity: identity, vault: &vault), "Chloe O’Connor")
        XCTAssertEqual(Cloaker.uncloak("Chloe O'Connor's note to Chloe.", vault: vault), "Anne-Marie O'Neil's note to Anne-Marie.")
    }

    func testTitlesAndMultiwordGivenNamesKeepTheFirstWrittenName() {
        let identity = nameIdentity(real: "Dr. Mary Jane Watson")
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("Mary is Dr. Mary Jane Watson", identity: identity, vault: &vault), "Chloe is Chloe Stone")
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe! Hello Chloe Stone.", vault: vault), "Hi Mary! Hello Dr. Mary Jane Watson.")
    }

    func testCommaSeparatedNamesNeedAnExplicitShortNamePair() {
        var identity = nameIdentity(real: "Mehta, Harsh")
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Mehta, Harsh", identity: identity, vault: &vault)
        XCTAssertEqual(Cloaker.uncloak("Chloe Stone and Chloe", vault: vault), "Mehta, Harsh and Chloe")
        identity.customPairs = [.init(real: "Harsh", alt: "Chloe")]
        _ = Cloaker.cloak("Harsh", identity: identity, vault: &vault)
        XCTAssertEqual(Cloaker.uncloak("Hi Chloe!", vault: vault), "Hi Harsh!")
    }

    func testLongLiteralAliasDoesNotRequireDeeplyNestedRegularExpressions() {
        var identity = AltIdentity()
        let alias = String(repeating: "x", count: 600)
        identity.customPairs = [.init(real: "private-value", alt: alias)]
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("private-value", identity: identity, vault: &vault), alias)
        XCTAssertEqual(Cloaker.uncloak("Value: " + alias, vault: vault), "Value: private-value")
        XCTAssertEqual(Cloaker.uncloak("Value: " + alias, vault: vault, isStreaming: true), "Value: ")
    }

    func testDeclaredNamesRespectWordBoundariesAndLongestMatch() {
        var identity = AltIdentity()
        identity.realName = "Ann"
        identity.altName = "Mila"
        identity.customPairs = [.init(real: "Ann Smith", alt: "Olivia Stone")]
        var vault = Cloaker.Vault()
        let original = "Ann Smith and Ann attended the Annual event."
        let cloaked = Cloaker.cloak(original, identity: identity, vault: &vault)
        XCTAssertEqual(cloaked, "Olivia Stone and Mila attended the Annual event.")
        XCTAssertEqual(Cloaker.uncloak(cloaked, vault: vault), original)
    }

    func testReplacementsDoNotCascadeThroughInjectedValues() {
        var identity = AltIdentity()
        identity.customPairs = [.init(real: "Alice", alt: "Bob"), .init(real: "Bob", alt: "Charlie")]
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("Alice and Bob", identity: identity, vault: &vault), "Bob and Charlie")
        XCTAssertEqual(Cloaker.uncloak("Bob and Charlie", vault: vault), "Alice and Bob")
        XCTAssertNotNil(identity.validationError) // UI rejects ambiguous configuration.
    }

    func testStructuredValuesRoundTripAndRemainStableAcrossTurns() {
        let original = "Email me at person@real.test, call +1 (415) 555-1212. IP 203.0.113.4. SSN 123-45-6789."
        var vault = Cloaker.Vault()
        let first = Cloaker.cloak(original, identity: .empty, vault: &vault)
        XCTAssertFalse(first.contains("person@real.test"))
        XCTAssertFalse(first.contains("+1 (415) 555-1212"))
        XCTAssertFalse(first.contains("203.0.113.4"))
        XCTAssertFalse(first.contains("123-45-6789"))
        XCTAssertEqual(Cloaker.uncloak(first, vault: vault), original)
        XCTAssertEqual(Cloaker.cloak(original, identity: .empty, vault: &vault), first)
    }

    func testEditingIdentityDoesNotChangeExistingVaultMappings() {
        var identity = AltIdentity()
        identity.realName = "Real Name"
        identity.altName = "Alt Name"
        var vault = Cloaker.Vault()
        _ = Cloaker.cloak("Real Name", identity: identity, vault: &vault)
        identity.altName = "New Alias"
        XCTAssertEqual(Cloaker.cloak("Real Name", identity: identity, vault: &vault), "Alt Name")
    }

    func testIdentityValidationAndWhitespace() {
        var identity = AltIdentity()
        identity.realName = "  Ann  "
        XCTAssertNotNil(identity.validationError)
        identity.altName = "  Olivia  "
        XCTAssertNil(identity.validationError)
        XCTAssertEqual(identity.altPairs.first?.real, "Ann")
        identity.customPairs = [.init(real: "Other", alt: "Olivia")]
        XCTAssertNotNil(identity.validationError)
    }

    func testIdentityRejectsAltValuesThatExposeRealGivenName() {
        var identity = nameIdentity(real: "Harsh Mehta", alt: "Harsh Stone")
        XCTAssertNotNil(identity.validationError)
        identity.altName = "Chloe Stone"
        XCTAssertNil(identity.validationError)
        identity.customPairs = [.init(real: "Project name", alt: "Team Harsh")]
        XCTAssertNotNil(identity.validationError)
    }

    func testConfiguredFirstFullAndMiddleNamesRestoreVariantsNotUsedInPrompt() {
        var identity = AltIdentity()
        identity.customPairs = [
            .init(real: "Harsh Savergaonkar", alt: "John Stone"),
            .init(real: "Harsh", alt: "John"),
            .init(real: "Harsh Example Savergaonkar", alt: "John Michael Stone")
        ]
        XCTAssertNil(identity.validationError)
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak("My son is Mr. Harsh Example Savergaonkar.", identity: identity, vault: &vault),
                       "My son is Mr. John Michael Stone.")
        let reply = "in a 60% share, and to my son, Mr. John Stone, born on "
        let expected = "in a 60% share, and to my son, Mr. Harsh Savergaonkar, born on "
        XCTAssertEqual(Cloaker.uncloak(reply, vault: vault), expected)
        XCTAssertEqual(Cloaker.uncloak("John and John Michael Stone", vault: vault), "Harsh and Harsh Example Savergaonkar")
        for count in 0...reply.count {
            let rendered = Cloaker.uncloak(String(reply.prefix(count)), vault: vault, isStreaming: true)
            XCTAssertTrue(expected.hasPrefix(rendered), "Incorrect partial restoration: \(rendered)")
        }
    }

    func testFirstNameActivatesConfiguredFullNameWithoutMixingFamilies() {
        for firstAlias in ["John", "Chloe"] {
            var identity = AltIdentity()
            identity.customPairs = [.init(real: "Harsh", alt: firstAlias),
                                    .init(real: "Harsh Savergaonkar", alt: "John Stone"),
                                    .init(real: "Priya Kapoor", alt: "Mary Jones")]
            var vault = Cloaker.Vault()
            _ = Cloaker.cloak("Harsh", identity: identity, vault: &vault)
            XCTAssertEqual(Cloaker.uncloak("Mr. John Stone and Mary Jones", vault: vault), "Mr. Harsh Savergaonkar and Mary Jones")
        }
    }

    func testAutomaticDetectionPreservesPercentagesDatesAndOrdinaryNumbers() {
        let text = "60% share. Born on 2001-01-23. Revenue 1234567890123456. Timestamp 1758360600. sku1234567890 and 12345678901234567."
        var vault = Cloaker.Vault()
        XCTAssertEqual(Cloaker.cloak(text, identity: .empty, vault: &vault), text)
        let privateText = "Card 4111 1111 1111 1111; call 4155551212; email person@example.org."
        let hidden = Cloaker.cloak(privateText, identity: .empty, vault: &vault)
        XCTAssertEqual(hidden, "Card [CARD_1]; call [PHONE_1]; email [EMAIL_1].")
        XCTAssertEqual(Cloaker.uncloak(hidden, vault: vault), privateText)
    }

    func testRepeatedAutomaticValuesUseOnePlaceholderWithoutCollidingWithLiteralTokens() {
        var vault = Cloaker.Vault()
        let text = "[EMAIL_1] and a@example.org, a@example.org, b@example.org"
        let hidden = Cloaker.cloak(text, identity: .empty, vault: &vault)
        XCTAssertEqual(hidden, "[EMAIL_1] and [EMAIL_2], [EMAIL_2], [EMAIL_3]")
        XCTAssertEqual(Cloaker.uncloak(hidden, vault: vault), text)
    }
}
