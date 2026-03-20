import AppKit

struct AppRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlUrl = "html_url"
    }
}

@MainActor @Observable
final class UpdateChecker {
    var availableRelease: AppRelease?

    private static let repo = "bradjenn/blink"
    private static let checkInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    private static let lastCheckKey = "blink.lastUpdateCheck"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var updateAvailable: Bool { availableRelease != nil }

    func checkIfNeeded() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let elapsed = Date().timeIntervalSince1970 - last
        guard elapsed > Self.checkInterval || last == 0 else { return }
        Task { await check() }
    }

    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            let latestVersion = String(release.tagName.trimmingPrefix("v"))

            if Self.isNewer(latestVersion, than: currentVersion) {
                availableRelease = release
            } else {
                availableRelease = nil
            }
        } catch {
            // Silent failure — update check is non-critical
        }
    }

    func openReleasePage() {
        guard let release = availableRelease,
              let url = URL(string: release.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    func dismiss() {
        availableRelease = nil
    }

    private static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(latestParts.count, currentParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
