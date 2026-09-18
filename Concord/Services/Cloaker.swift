import Foundation

/// Stateless PII-cloaking helpers. A per-conversation "vault" (`[realValue: altValue]`)
/// records every swap so replacements stay consistent across turns and can be reversed.
///
/// `cloak` swaps real → fake before a message goes to the gateway; `uncloak` swaps fake →
/// real when the reply streams back for display. Only the fake identity ever leaves the app.
enum Cloaker {
    /// Replaces declared identity values and structured PII in `text` with fakes, recording
    /// each swap in `vault`. Declared pairs are applied first (case-insensitive), then regex
    /// scanning handles anything else (email, phone, credit-card, SSN, IPv4).
    static func cloak(_ text: String, identity: AltIdentity, vault: inout [String: String]) -> String {
        var result = text

        // 1. Declared field pairs — longest real first (altPairs is pre-sorted).
        for pair in identity.altPairs {
            guard !pair.real.isEmpty, !pair.alt.isEmpty else { continue }
            guard result.range(of: pair.real, options: .caseInsensitive) != nil else { continue }
            result = result.replacingOccurrences(of: pair.real, with: pair.alt, options: [.caseInsensitive])
            vault[pair.real] = pair.alt
        }

        // 2. Structured PII. Detect on the current text (no fakes injected yet), then apply
        //    all replacements longest-real-first, so a longer match wins over any substring
        //    and we never re-cloak a value we just inserted.
        let alreadyFake = Set(vault.values)
        var discovered: [String: String] = [:]
        for detector in detectors {
            let ns = result as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in detector.regex.matches(in: result, options: [], range: range) {
                let value = ns.substring(with: match.range)
                if value.isEmpty { continue }
                if alreadyFake.contains(value) { continue }   // an injected/declared fake
                if discovered[value] != nil { continue }       // already handled this pass
                if let known = vault[value] {                   // recurring real value → reuse
                    discovered[value] = known
                } else {
                    let fake = detector.make(value)
                    vault[value] = fake
                    discovered[value] = fake
                }
            }
        }
        for (real, fake) in discovered.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: real, with: fake)
        }
        return result
    }

    /// Reverses every swap in `vault` (alt → real), replacing longer alt strings first so a
    /// longer fake is restored before any fake that is a substring of it.
    static func uncloak(_ text: String, vault: [String: String]) -> String {
        var result = text
        let pairs = vault
            .map { (real: $0.key, alt: $0.value) }
            .filter { !$0.alt.isEmpty }
            .sorted { $0.alt.count > $1.alt.count }
        for pair in pairs {
            guard result.range(of: pair.alt, options: .caseInsensitive) != nil else { continue }
            result = result.replacingOccurrences(of: pair.alt, with: pair.real, options: [.caseInsensitive])
        }
        return result
    }

    // MARK: - Detectors

    private struct Detector {
        let regex: NSRegularExpression
        let make: (String) -> String
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants known to be valid.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let detectors: [Detector] = [
        Detector(regex: regex(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#), make: fakeEmail),
        Detector(regex: regex(#"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#), make: fakeIPv4),
        Detector(regex: regex(#"\b\d{3}-\d{2}-\d{4}\b"#), make: maskDigits),
        Detector(regex: regex(#"(?:\b\d{4}[ \-]?\d{4}[ \-]?\d{4}[ \-]?\d{4}\b)|(?:\b\d{13,16}\b)"#), make: maskDigits),
        Detector(regex: regex(#"(?<!\d)(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{3}\)|\d{3})[\s.\-]?\d{3}[\s.\-]?\d{4}(?!\d)"#), make: maskDigits),
    ]

    // MARK: - Deterministic fake generators

    /// A stable (per-value, launch-independent) 64-bit FNV-1a hash so the same real value
    /// always maps to the same fake shape.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func fakeEmail(_ value: String) -> String {
        let suffix = String(format: "%08x", UInt32(truncatingIfNeeded: stableHash(value)))
        return "user\(suffix)@example.com"
    }

    private static func fakeIPv4(_ value: String) -> String {
        func octet(_ salt: String) -> Int { Int(stableHash("ip:\(value):\(salt)") % 254) + 1 }
        return "10.\(octet("a")).\(octet("b")).\(octet("c"))"
    }

    /// Format-preserving: keeps every non-digit (spaces, dashes, parens, `+`) and replaces
    /// each digit with a deterministic one, so the fake has the exact same shape.
    private static func maskDigits(_ value: String) -> String {
        var out = ""
        var index = 0
        for character in value {
            if character.isNumber {
                let digit = stableHash("d:\(value):\(index)") % 10
                out.append(Character("\(digit)"))
                index += 1
            } else {
                out.append(character)
            }
        }
        return out
    }
}
