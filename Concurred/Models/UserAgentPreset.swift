import Foundation

struct UserAgentPreset: Identifiable {
    enum Device {
        case mac, windows, iPhone, android, terminal, custom
        var isPhone: Bool { self == .iPhone || self == .android }
    }

    let name: String
    let value: String
    let device: Device
    var id: String { name }

    static let all: [UserAgentPreset] = [
        .init(name: "System default", value: "", device: .mac),
        .init(name: "Chrome — macOS", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", device: .mac),
        .init(name: "Safari — macOS", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", device: .mac),
        .init(name: "Firefox — macOS", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:126.0) Gecko/20100101 Firefox/126.0", device: .mac),
        .init(name: "Chrome — Windows", value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", device: .windows),
        .init(name: "Chrome — Android", value: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36", device: .android),
        .init(name: "Safari — iPhone", value: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", device: .iPhone),
        .init(name: "curl", value: "curl/8.4.0", device: .terminal),
    ]

    static func matching(_ value: String) -> UserAgentPreset {
        let value = value.trimmingCharacters(in: .whitespaces)
        return all.first { $0.value == value }
            ?? .init(name: "Custom User-Agent", value: value, device: .custom)
    }
}
