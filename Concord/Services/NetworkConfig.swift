import Foundation
import Observation
import SwiftUI

/// Persisted network transport settings: a custom User-Agent and/or an outbound proxy,
/// applied to every request the app makes to an LLM provider.
struct NetworkSettings: Codable, Equatable {
    var userAgent: String = ""
    var proxyEnabled: Bool = false
    /// false = HTTP proxy, true = SOCKS5 proxy.
    var proxyIsSOCKS: Bool = false
    var proxyHost: String = ""
    var proxyPort: Int = 0

    private static let defaultsKey = "network.settings"

    static func load() -> NetworkSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(NetworkSettings.self, from: data)
        else {
            return NetworkSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// Builds `URLSession`s configured from the persisted `NetworkSettings` — a custom
/// User-Agent header and/or an HTTP or SOCKS5 proxy — for use by `ChatClient`.
enum NetworkConfig {
    static func session() -> URLSession {
        let settings = NetworkSettings.load()
        let config = URLSessionConfiguration.default

        if !settings.userAgent.isEmpty {
            config.httpAdditionalHeaders = ["User-Agent": settings.userAgent]
        }

        if settings.proxyEnabled, !settings.proxyHost.isEmpty, settings.proxyPort > 0 {
            if settings.proxyIsSOCKS {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: 1,
                    kCFNetworkProxiesSOCKSProxy as String: settings.proxyHost,
                    kCFNetworkProxiesSOCKSPort as String: settings.proxyPort,
                ]
            } else {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: 1,
                    kCFNetworkProxiesHTTPProxy as String: settings.proxyHost,
                    kCFNetworkProxiesHTTPPort as String: settings.proxyPort,
                    kCFNetworkProxiesHTTPSEnable as String: 1,
                    kCFNetworkProxiesHTTPSProxy as String: settings.proxyHost,
                    kCFNetworkProxiesHTTPSPort as String: settings.proxyPort,
                ]
            }
        }

        return URLSession(configuration: config)
    }
}

/// Editable, saveable wrapper around `NetworkSettings` for the Settings UI.
@MainActor
@Observable
final class NetworkStore {
    var userAgent: String
    var proxyEnabled: Bool
    var proxyIsSOCKS: Bool
    var proxyHost: String
    var proxyPortText: String

    init() {
        let settings = NetworkSettings.load()
        userAgent = settings.userAgent
        proxyEnabled = settings.proxyEnabled
        proxyIsSOCKS = settings.proxyIsSOCKS
        proxyHost = settings.proxyHost
        proxyPortText = settings.proxyPort > 0 ? String(settings.proxyPort) : ""
    }

    func save() {
        var settings = NetworkSettings()
        settings.userAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.proxyEnabled = proxyEnabled
        settings.proxyIsSOCKS = proxyIsSOCKS
        settings.proxyHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.proxyPort = Int(proxyPortText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        settings.save()
    }
}
