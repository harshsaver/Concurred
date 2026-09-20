import Foundation

/// Best-effort substitutions for declared values and recognized structured personal data.
/// Ranges are resolved against the original text so replacements never cascade.
enum Cloaker {
    /// Used mappings and explicitly configured variants of those values restore
    /// responses. Metadata stays stable if Alt ID is edited later.
    struct Vault {
        var substitutions: [(real: String, alt: String)] {
            mappings.values.map { ($0.real, $0.alt) }.sorted { $0.real < $1.real }
        }

        mutating func hide(_ value: String, kind: String, in text: String) {
            guard mappings[value] == nil else { return }
            record(Mapping(real: value, alt: placeholder(kind, in: text)))
        }

        fileprivate func placeholder(_ kind: String, in text: String) -> String {
            let reserved = Set(mappings.values.map { $0.alt.lowercased() })
            var number = 1
            while reserved.contains("[\(kind)_\(number)]".lowercased()) || text.localizedCaseInsensitiveContains("[\(kind)_\(number)]") {
                number += 1
            }
            return "[\(kind)_\(number)]"
        }

        fileprivate var mappings: [String: Mapping] = [:]
        fileprivate var restorationRules: [Rule] = []

        fileprivate mutating func record(_ mapping: Mapping) {
            guard mappings[mapping.real] != mapping else { return }
            mappings[mapping.real] = mapping
            restorationRules = Cloaker.rules(for: Array(mappings.values), restoring: true)
        }
    }

    fileprivate struct Mapping: Equatable {
        let real: String
        let alt: String
        let isName: Bool
        let realGivenName: String?
        let altGivenName: String?

        init(real: String, alt: String, isName: Bool = false) {
            self.real = real
            self.alt = alt
            self.isName = isName
            realGivenName = isName ? AltIdentity.givenName(in: real) : nil
            altGivenName = isName ? AltIdentity.givenName(in: alt) : nil
        }
    }

    fileprivate struct Rule {
        let source: String
        let value: String
        let mapping: Mapping
        let isShortName: Bool
        let match: NSRegularExpression
        let foldedSource: String
        let requiresWordStart: Bool
    }

    private struct Replacement {
        let range: NSRange
        let value: String
        let mapping: Mapping
    }

    static func cloak(_ text: String, identity: AltIdentity, vault: inout Vault) -> String {
        let ns = text as NSString
        // Keep earlier swaps stable if the identity is edited during this conversation.
        let name = identity.realName.trimmingCharacters(in: .whitespacesAndNewlines)
        var pairs = identity.altPairs.map { Mapping(real: $0.real, alt: $0.alt, isName: $0.real == name) }
        for mapping in vault.mappings.values {
            pairs.removeAll { $0.real.caseInsensitiveCompare(mapping.real) == .orderedSame }
            pairs.append(mapping)
        }
        let outboundRules = rules(for: pairs, restoring: false)
        var replacements = matches(in: text, rules: outboundRules)
        // A name embedded in a link must not leak or turn the URL into a name
        // with spaces. Substitute that whole link and restore it as one value.
        for link in links.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let scheme = link.url?.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  !replacements.contains(where: { NSIntersectionRange($0.range, link.range).length > 0 }) else { continue }
            let real = ns.substring(with: link.range)
            guard outboundRules.contains(where: {
                $0.mapping.isName && $0.match.firstMatch(in: real, range: NSRange(real.startIndex..., in: real)) != nil
            }) else { continue }
            let mapping = Mapping(real: real, alt: vault.mappings[real]?.alt ?? "https://example.com/\(UUID().uuidString.lowercased())")
            replacements.append(Replacement(range: link.range, value: mapping.alt, mapping: mapping))
        }
        for detector in detectors {
            for match in detector.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                // Declared values and known replacements take priority over automatic detection.
                guard !replacements.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
                let real = ns.substring(with: match.range)
                guard detector.accepts(real, text, match.range) else { continue }
                let reservedText = text + pairs.map(\.alt).joined(separator: " ")
                let fake = vault.mappings[real]?.alt ?? vault.placeholder(detector.kind, in: reservedText)
                let mapping = Mapping(real: real, alt: fake)
                vault.record(mapping)
                replacements.append(Replacement(range: match.range, value: fake, mapping: mapping))
            }
        }
        let selected = nonOverlapping(replacements)
        for item in selected { vault.record(item.mapping) }
        // A reply can use another explicitly configured version of the same name.
        // Activate connected pairs (e.g. full / first / middle name) even when that
        // exact spelling did not appear in this request. Never invent a variant.
        var active = selected.map(\.mapping)
        var remaining = pairs.filter { candidate in !active.contains(candidate) }
        while let index = remaining.firstIndex(where: { candidate in
            active.contains { related(candidate, $0) }
        }) {
            let mapping = remaining.remove(at: index)
            vault.record(mapping)
            active.append(mapping)
        }
        return replacing(text, with: selected)
    }

    private static func related(_ lhs: Mapping, _ rhs: Mapping) -> Bool {
        func contains(_ whole: String, _ part: String) -> Bool {
            let expression = rule(source: part, value: "", mapping: lhs, isShortName: false).match
            return expression.firstMatch(in: whole, range: NSRange(whole.startIndex..., in: whole)) != nil
        }
        // Users may choose different aliases for each spelling. The configured
        // real values connect the variants; aliases need not share a first name.
        return contains(lhs.real, rhs.real) || contains(rhs.real, lhs.real)
    }

    static func uncloak(_ text: String, vault: Vault, isStreaming: Bool = false) -> String {
        let rules = vault.restorationRules
        // Wait for enough of a streamed alias to distinguish a first name from a
        // full name. Never display fragments such as "Harsh St" for "Chloe Stone".
        let end = isStreaming ? rules.compactMap { incompleteStart(in: text, rule: $0) }.min() ?? text.endIndex : text.endIndex
        let visible = String(text[..<end])
        return replacing(visible, with: nonOverlapping(matches(in: visible, rules: rules)))
    }

    private static func rules(for mappings: [Mapping], restoring: Bool) -> [Rule] {
        var candidates: [Rule] = []
        for mapping in mappings {
            let source = restoring ? mapping.alt : mapping.real
            let value = restoring ? mapping.real : mapping.alt
            candidates.append(rule(source: source, value: value, mapping: mapping, isShortName: false))
            if mapping.isName,
               let givenSource = restoring ? mapping.altGivenName : mapping.realGivenName,
               let givenValue = restoring ? mapping.realGivenName : mapping.altGivenName,
               !givenSource.isEmpty, !givenValue.isEmpty, canonical(givenSource) != canonical(source) {
                candidates.append(rule(source: givenSource, value: givenValue, mapping: mapping, isShortName: true))
            }
        }
        return Dictionary(grouping: candidates, by: { canonical($0.source) }).values.compactMap { group in
            // Outbound explicit pairs override inferred first names. On replies,
            // ambiguous aliases stay unchanged instead of guessing an identity.
            let explicit = group.filter { !$0.isShortName }
            let available = !restoring && !explicit.isEmpty ? explicit : group
            guard Set(available.map { canonical($0.value) }).count == 1 else { return nil }
            return available.sorted { $0.mapping.real < $1.mapping.real }.first
        }
    }

    private static func rule(source: String, value: String, mapping: Mapping, isShortName: Bool) -> Rule {
        let requiresWordStart = source.unicodeScalars.first.map { wordCharacters.contains($0) } == true
        let start = requiresWordStart ? #"(?<![\p{L}\p{M}\p{N}_])"# : ""
        let end = source.unicodeScalars.last.map { wordCharacters.contains($0) } == true ? #"(?![\p{L}\p{M}\p{N}_])"# : ""
        var parts: [String] = []
        for character in source {
            if mapping.isName && character.isWhitespace {
                if parts.last != #"\s+"# { parts.append(#"\s+"#) }
            } else if mapping.isName && "'’".contains(character) {
                parts.append("['’]")
            } else {
                parts.append(NSRegularExpression.escapedPattern(for: String(character)))
            }
        }
        return Rule(source: source, value: value, mapping: mapping, isShortName: isShortName,
                    match: try! NSRegularExpression(pattern: start + parts.joined() + end, options: [.caseInsensitive]),
                    foldedSource: folded(source, isName: mapping.isName), requiresWordStart: requiresWordStart)
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters).union(CharacterSet(charactersIn: "_"))

    private static func folded(_ value: String, isName: Bool) -> String {
        let value = value.precomposedStringWithCanonicalMapping.lowercased()
        return isName ? value.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) : value
    }

    private static func incompleteStart(in text: String, rule: Rule) -> String.Index? {
        var suffix = ""
        var length = 0
        let limit = rule.foldedSource.utf16.count
        var index = text.endIndex
        var start: String.Index?
        // Only inspect the tail that could still be an alias, not the entire
        // reply. No nested regex or token-boundary assumptions about SSE chunks.
        while index > text.startIndex {
            index = text.index(before: index)
            let part = folded(String(text[index]), isName: rule.mapping.isName)
            if !(rule.mapping.isName && part == " " && suffix.hasPrefix(" ")) {
                suffix = part + suffix
                length += part.utf16.count
            }
            if length > limit { break }
            if rule.requiresWordStart && index > text.startIndex,
               let previous = text[text.index(before: index)].unicodeScalars.last,
               wordCharacters.contains(previous) { continue }
            if rule.foldedSource.hasPrefix(suffix) { start = index }
        }
        return start
    }

    private static func canonical(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func matches(in text: String, rules: [Rule]) -> [Replacement] {
        let range = NSRange(text.startIndex..., in: text)
        let protected = links.matches(in: text, range: range).map(\.range)
            + detectors[0].regex.matches(in: text, range: range).map(\.range)
        return rules.flatMap { rule in
            rule.match.matches(in: text, range: range).compactMap { match in
                // A name appearing inside an email address or URL is not a name
                // reference. Those values have their own exact substitutions.
                if rule.mapping.isName && protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    return nil
                }
                return Replacement(range: match.range, value: rule.value, mapping: rule.mapping)
            }
        }
    }

    private static func nonOverlapping(_ values: [Replacement]) -> [Replacement] {
        var result: [Replacement] = []
        var end = 0
        for value in values.sorted(by: {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            return $0.mapping.real < $1.mapping.real
        }) where value.range.location >= end {
            result.append(value)
            end = NSMaxRange(value.range)
        }
        return result
    }

    private static func replacing(_ text: String, with replacements: [Replacement]) -> String {
        let result = NSMutableString(string: text)
        for replacement in replacements.reversed() {
            result.replaceCharacters(in: replacement.range, with: replacement.value)
        }
        return result as String
    }

    // MARK: - Detectors

    private struct Detector {
        let regex: NSRegularExpression
        let kind: String
        var accepts: (String, String, NSRange) -> Bool = { _, _, _ in true }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants known to be valid.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let links = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static let detectors: [Detector] = [
        Detector(regex: regex(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#), kind: "EMAIL"),
        Detector(regex: regex(#"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#), kind: "IP_ADDRESS"),
        Detector(regex: regex(#"(?<![\p{L}\d_])\d{3}-\d{2}-\d{4}(?![\p{L}\d_])"#), kind: "SSN"),
        Detector(regex: regex(#"(?<![\p{L}\d_])(?:\d[ -]?){12,18}\d(?![\p{L}\d_])"#), kind: "CARD", accepts: { value, _, _ in validCard(value) }),
        Detector(regex: regex(#"(?<![\p{L}\d_+])(?:\+\d{1,3}[ \.\-]?)?(?:\(\d{3}\)|\d{3})[ \.\-]?\d{3}[ \.\-]?\d{4}(?![\p{L}\d_])"#), kind: "PHONE", accepts: { value, text, range in
            if value.contains(where: { !$0.isNumber }) { return true }
            let prefix = (text as NSString).substring(to: range.location).suffix(40)
            return prefix.range(of: #"(?i)\b(phone|mobile|call|tel|telephone|contact|fax)\b[^\n]*$"#, options: .regularExpression) != nil
        }),
    ]

    private static func validCard(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { sum, item in
            let digit = item.offset.isMultiple(of: 2) ? item.element : item.element * 2
            return sum + (digit > 9 ? digit - 9 : digit)
        }
        return sum.isMultiple(of: 10)
    }
}
