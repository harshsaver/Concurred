import Foundation
import NaturalLanguage

/// Detection proposes exact source text. It never rewrites a message or sends it out.
enum LocalIdentifierDetector {
    struct Candidate: Identifiable, Hashable, Sendable {
        let text: String
        let kind: String
        var id: String { text }
    }

    static func candidates(in text: String) -> [Candidate] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var result: [Candidate] = []
        var seen: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            let kinds: [NLTag: String] = [.personalName: "PERSON", .placeName: "PLACE", .organizationName: "ORGANIZATION"]
            if let tag, let kind = kinds[tag] {
                let value = String(text[range])
                if seen.insert(value.lowercased()).inserted { result.append(Candidate(text: value, kind: kind)) }
            }
            return true
        }
        let addresses = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        for match in addresses.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let value = (text as NSString).substring(with: match.range)
            if seen.insert(value.lowercased()).inserted { result.append(Candidate(text: value, kind: "ADDRESS")) }
        }
        return result
    }
}

/// A local snapshot: sending it uses these exact substitutions, not another random pass.
struct CloakReview: Identifiable {
    let id = UUID()
    let original: [WireMessage]
    let identity: AltIdentity
    private let initialVault: Cloaker.Vault
    private(set) var vault: Cloaker.Vault
    private(set) var outgoing: [WireMessage] = []
    private(set) var hidden: [LocalIdentifierDetector.Candidate] = []

    init(original: [WireMessage], identity: AltIdentity, vault: Cloaker.Vault) {
        self.original = original
        self.identity = identity
        initialVault = vault
        self.vault = vault
        rebuild()
    }

    mutating func toggle(_ candidate: LocalIdentifierDetector.Candidate) {
        if hidden.contains(candidate) { hidden.removeAll { $0 == candidate } }
        else { hidden.append(candidate) }
        rebuild()
    }

    func needsReview(_ value: String) -> Bool {
        var copy = vault
        return Cloaker.cloak(value, identity: identity, vault: &copy) == value
    }

    private mutating func rebuild() {
        vault = initialVault
        let text = original.map(\.content).joined(separator: "\n\n") + identity.altPairs.map(\.alt).joined(separator: " ")
        for candidate in hidden { vault.hide(candidate.text, kind: candidate.kind, in: text) }
        outgoing = original.map { WireMessage(role: $0.role, content: Cloaker.cloak($0.content, identity: identity, vault: &vault)) }
    }
}
