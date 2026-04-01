import Foundation

enum BrowserURLResolver {
    private static let localHostSuffixes = [".local", ".localhost", ".test", ".internal"]
    private static let explicitlyAllowedSchemes = Set(["http", "https", "file", "about"])

    static func resolve(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           explicitlyAllowedSchemes.contains(scheme) {
            return url
        }

        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }

        guard let host = hostCandidate(from: trimmed),
              looksLikeBrowsableHost(host) else {
            return nil
        }

        let scheme = defaultScheme(forHost: host)
        return URL(string: "\(scheme)\(trimmed)")
    }

    private static func hostCandidate(from value: String) -> String? {
        let slashSplit = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return slashSplit.first.map(String.init)
    }

    private static func looksLikeBrowsableHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        let hostWithoutPort = normalizedHost.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? normalizedHost

        if normalizedHost == "localhost" || normalizedHost.hasPrefix("localhost:") {
            return true
        }

        if normalizedHost == "127.0.0.1" || normalizedHost.hasPrefix("127.0.0.1:") {
            return true
        }

        if localHostSuffixes.contains(where: { hostWithoutPort.hasSuffix($0) }) {
            return true
        }

        return hostWithoutPort.contains(".")
    }

    private static func defaultScheme(forHost host: String) -> String {
        let normalizedHost = host.lowercased()
        let hostWithoutPort = normalizedHost.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? normalizedHost

        if hostWithoutPort == "localhost" || hostWithoutPort == "127.0.0.1" {
            return "http://"
        }

        if localHostSuffixes.contains(where: { hostWithoutPort.hasSuffix($0) }) {
            return "http://"
        }

        return "https://"
    }
}
