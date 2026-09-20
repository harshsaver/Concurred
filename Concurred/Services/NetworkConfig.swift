import Foundation
import Observation

struct NetworkSettings: Codable, Equatable {
    var userAgent = ""
    var proxyEnabled = false
    var proxyIsSOCKS = false
    var proxyHost = ""
    var proxyPort = 0

    private static let defaultsKey = "network.settings"

    static func load() throws -> NetworkSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return NetworkSettings() }
        return try JSONDecoder().decode(NetworkSettings.self, from: data)
    }

    var validationError: String? {
        if userAgent.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "The User-Agent must be a single line without control characters."
        }
        guard proxyEnabled else { return nil }
        guard !proxyHost.isEmpty, !proxyHost.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: "http://\(proxyHost)"),
              components.host?.isEmpty == false, components.user == nil, components.password == nil,
              components.path.isEmpty, components.query == nil, components.fragment == nil else {
            return "Enter a proxy hostname or IP address, without a scheme, path, or credentials."
        }
        if components.port != nil { return "Enter the proxy port in the Port field." }
        guard (1...65535).contains(proxyPort) else { return "Enter a proxy port between 1 and 65535." }
        return nil
    }

    func save() throws {
        if let message = validationError { throw NetworkError.invalidSettings(message) }
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}

enum NetworkError: LocalizedError {
    case invalidSettings(String)
    var errorDescription: String? {
        switch self { case .invalidSettings(let message): return message }
    }
}

/// Provider requests never silently bypass an enabled, invalid proxy.
enum NetworkConfig {
    static func session() throws -> URLSession {
        let settings: NetworkSettings
        do { settings = try NetworkSettings.load() }
        catch { throw NetworkError.invalidSettings("Network settings could not be read. Open Network and save valid settings before retrying.") }
        return try session(settings: settings)
    }

    static func session(settings: NetworkSettings) throws -> URLSession {
        if let message = settings.validationError { throw NetworkError.invalidSettings(message) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        if !settings.userAgent.isEmpty { config.httpAdditionalHeaders = ["User-Agent": settings.userAgent] }
        if settings.proxyEnabled {
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
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
}

/// Do not forward credentials or conversation bodies through provider redirects.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class NetworkStore {
    var settings = NetworkSettings()
    var proxyPortText = ""
    var errorText: String?
    private(set) var savedSettings: NetworkSettings?

    init() {
        do {
            settings = try NetworkSettings.load()
            savedSettings = settings
            proxyPortText = settings.proxyPort > 0 ? String(settings.proxyPort) : ""
        } catch {
            errorText = "Saved network settings could not be read. Enter valid settings and save to replace them."
        }
    }

    var draft: NetworkSettings {
        var value = settings
        value.userAgent = value.userAgent.trimmingCharacters(in: .whitespaces)
        value.proxyHost = value.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        value.proxyPort = Int(proxyPortText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return value
    }
    var hasChanges: Bool { draft != savedSettings }

    func save() {
        do {
            try draft.save()
            settings = draft
            savedSettings = settings
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
}
