import Foundation

/// A paired real/alt identity used by the Cloak feature. The `real*` fields hold the
/// user's genuine PII; the `alt*` fields hold a realistic-but-fake stand-in. When Cloak
/// is on, outgoing messages swap real → alt and the reply swaps alt → real for display.
///
/// The whole identity is persisted as JSON in the macOS Keychain (it's real PII, so it
/// never touches UserDefaults).
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
        "mailinator.com", "barbarbu.fr", "example.net", "trashmail.com",
    ]

    /// Returns an identity with only the ALT fields filled with plausible fakes; the real
    /// fields are left empty.
    static func generatedAlt() -> AltIdentity {
        var identity = AltIdentity()
        identity.fillAlt()
        return identity
    }

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

        let area = Int.random(in: 200 ... 989)
        let mid = Int.random(in: 200 ... 999)
        let last4 = Int.random(in: 0 ... 9999)
        altPhone = String(format: "+1 (%03d) %03d-%04d", area, mid, last4)

        let number = Int.random(in: 12 ... 9987)
        let street = Self.streets.randomElement() ?? "Elm Street"
        let city = Self.cities.randomElement() ?? "Portland"
        let postal = String(format: "%05d", Int.random(in: 10000 ... 99999))
        let country = Self.countries.randomElement() ?? "USA"
        altAddress = "\(number) \(street), \(city) \(postal), \(country)"

        let month = Int.random(in: 1 ... 12)
        let day = Int.random(in: 1 ... 28)
        let year = Int.random(in: 60 ... 99)
        altDOB = "\(month)/\(day)/\(String(format: "%02d", year))"
    }

    // MARK: - Keychain persistence

    private static let store = KeychainSecretStore(service: "dev.october.concord")
    private static let account = "altIdentity"

    static func load() -> AltIdentity {
        guard let json = store.value(for: account),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AltIdentity.self, from: data)
        else { return .empty }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8)
        else { return }
        Self.store.set(json, for: Self.account)
    }
}

// A tolerant decoder (in an extension, so the default initializer is preserved) lets
// identities saved before a field existed — e.g. before `customPairs` — still decode.
extension AltIdentity {
    private enum CodingKeys: String, CodingKey {
        case realName, altName, realEmail, altEmail, realPhone, altPhone
        case realAddress, altAddress, realDOB, altDOB, customPairs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        realName = try container.decodeIfPresent(String.self, forKey: .realName) ?? ""
        altName = try container.decodeIfPresent(String.self, forKey: .altName) ?? ""
        realEmail = try container.decodeIfPresent(String.self, forKey: .realEmail) ?? ""
        altEmail = try container.decodeIfPresent(String.self, forKey: .altEmail) ?? ""
        realPhone = try container.decodeIfPresent(String.self, forKey: .realPhone) ?? ""
        altPhone = try container.decodeIfPresent(String.self, forKey: .altPhone) ?? ""
        realAddress = try container.decodeIfPresent(String.self, forKey: .realAddress) ?? ""
        altAddress = try container.decodeIfPresent(String.self, forKey: .altAddress) ?? ""
        realDOB = try container.decodeIfPresent(String.self, forKey: .realDOB) ?? ""
        altDOB = try container.decodeIfPresent(String.self, forKey: .altDOB) ?? ""
        customPairs = try container.decodeIfPresent([CustomPair].self, forKey: .customPairs) ?? []
    }
}
