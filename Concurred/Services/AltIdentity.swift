import Foundation

/// A paired real/alt identity used by the Cloak feature. The `real*` fields hold the
/// user's genuine PII; the `alt*` fields hold a realistic-but-fake stand-in. When Cloak
/// is on, outgoing messages swap real → alt and the reply swaps alt → real for display.
///
/// Stored locally with owner-only file permissions, so opening Alt ID never requires
/// Keychain authentication. This file is not separately encrypted by the app.
struct AltIdentity: Codable, Equatable {
    /// A user-defined real → alt swap beyond the fixed fields (e.g. a relative's name).
    struct CustomPair: Codable, Equatable, Identifiable {
        var id = UUID()
        var real = ""
        var alt = ""
    }

    var realName = ""
    var altName = ""
    var realEmail = ""
    var altEmail = ""
    var realPhone = ""
    var altPhone = ""
    var realAddress = ""
    var altAddress = ""
    var realDOB = ""
    var altDOB = ""
    /// Arbitrary extra swaps the user adds themselves.
    var customPairs: [CustomPair] = []

    static let empty = AltIdentity()

    /// The Name field uses given-name-first order. Foundation recognizes titles,
    /// but its full parser can incorrectly swap hyphenated given/family names.
    /// Preserve the first written name token, including hyphens and apostrophes.
    static func givenName(in name: String) -> String? {
        guard !name.contains(",") else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let prefix = formatter.personNameComponents(from: name)?.namePrefix ?? ""
        let words = name.split(whereSeparator: \.isWhitespace)
            .dropFirst(prefix.split(whereSeparator: \.isWhitespace).count)
        guard let first = words.first, first.contains(where: \.isLetter),
              !first.hasSuffix(".") else { return nil }
        return String(first)
    }

    // MARK: - Non-empty real → alt pairs

    /// The declared pairs that have both a real and an alt value, sorted longest-real-first
    /// so longer strings are replaced before shorter substrings during cloaking.
    var altPairs: [(real: String, alt: String)] {
        var candidates: [(String, String)] = [
            (realName, altName),
            (realEmail, altEmail),
            (realPhone, altPhone),
            (realAddress, altAddress),
            (realDOB, altDOB),
        ]
        candidates.append(contentsOf: customPairs.map { ($0.real, $0.alt) })
        return candidates
            .map { ($0.0.trimmingCharacters(in: .whitespacesAndNewlines), $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
            .sorted { $0.0.count > $1.0.count }
            .map { (real: $0.0, alt: $0.1) }
    }

    // MARK: - Realistic-fake generation

    private static let firstNames = [
        "Liam", "Emma", "Noah", "Olivia", "Ethan", "Ava", "Mason", "Sophia",
        "Lucas", "Isla", "Hugo", "Mila", "Leo", "Chloe", "Adam",
    ]
    private static let lastNames = [
        "Bennett", "Carter", "Dumont", "Ellis", "Fischer", "Girard", "Holt",
        "Ivarsson", "Keller", "Laurent", "Moreau", "Novak", "Petit", "Renaud", "Stone",
    ]
    private static let streets = [
        "Maple Avenue", "Rue des Lilas", "Birch Lane", "Kingsway", "Elm Street",
        "Rue du Marché", "Cedar Court", "Highfield Road", "Rue Bellevue", "Park Terrace",
    ]
    private static let cities = [
        "Portland", "Lyon", "Bristol", "Utrecht", "Aarhus",
        "Nantes", "Leeds", "Ghent", "Turku", "Rennes",
    ]
    private static let countries = [
        "USA", "France", "United Kingdom", "Netherlands",
        "Denmark", "Belgium", "Finland", "Ireland",
    ]
    private static let emailDomains = [
        "example.com", "example.net", "example.org",
    ]

    /// Regenerates only the alt values, preserving whatever real values are set.
    mutating func refreshAlt() {
        fillAlt()
    }

    private mutating func fillAlt() {
        let first = Self.firstNames.randomElement() ?? "Alex"
        let last = Self.lastNames.randomElement() ?? "Stone"
        altName = "\(first) \(last)"

        let tag = Int.random(in: 10 ... 999)
        let domain = Self.emailDomains.randomElement() ?? "mailinator.com"
        altEmail = "\(first.lowercased()).\(last.lowercased())\(tag)@\(domain)"

        altPhone = String(format: "+1 (202) 555-%04d", Int.random(in: 100 ... 199))

        let number = Int.random(in: 12 ... 9987)
        let street = Self.streets.randomElement() ?? "Elm Street"
        let city = Self.cities.randomElement() ?? "Portland"
        let postal = String(format: "%05d", Int.random(in: 10000 ... 99999))
        let country = Self.countries.randomElement() ?? "USA"
        altAddress = "\(number) \(street), \(city) \(postal), \(country)"

        let month = Int.random(in: 1 ... 12)
        let day = Int.random(in: 1 ... 28)
        let year = Int.random(in: 1960 ... 1999)
        altDOB = String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Local persistence

    static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("dev.october.concord/alt-identity.json")

    static func load(from fileURL: URL = Self.fileURL) throws -> AltIdentity {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return .empty
        }
        return try JSONDecoder().decode(AltIdentity.self, from: data)
    }

    func save(to fileURL: URL = Self.fileURL) throws {
        if let error = validationError { throw IdentityError(message: error) }
        let data = try JSONEncoder().encode(self)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    struct IdentityError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var validationError: String? {
        let fields = [(realName, altName), (realEmail, altEmail), (realPhone, altPhone),
                      (realAddress, altAddress), (realDOB, altDOB)] + customPairs.map { ($0.real, $0.alt) }
        if fields.contains(where: { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every real value needs an alt value."
        }
        let pairs = altPairs
        let real = pairs.map { $0.real.lowercased() }
        let alt = pairs.map { $0.alt.lowercased() }
        if Set(real).count != real.count || Set(alt).count != alt.count {
            return "Use a unique real value and alt value for each pair."
        }
        if alt.contains(where: { replacement in real.contains(where: { replacement.contains($0) }) }) {
            return "Alt values must not contain a real value from any pair."
        }
        if let given = Self.givenName(in: realName) {
            let pattern = #"(?<![\p{L}\p{M}\p{N}_])"# + NSRegularExpression.escapedPattern(for: given) + #"(?![\p{L}\p{M}\p{N}_])"#
            let name = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if alt.contains(where: { name.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) {
                return "Alt values must not contain your real first name."
            }
        }
        return nil
    }
}
