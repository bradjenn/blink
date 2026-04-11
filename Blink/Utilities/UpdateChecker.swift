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

enum UpdateCheckAlert {
    case updateAvailable(AppRelease)
    case upToDate(currentVersion: String)
    case failed

    var title: String {
        switch self {
        case .updateAvailable(let release):
            return "\(release.name) Available"
        case .upToDate:
            return "Blink Is Up to Date"
        case .failed:
            return "Update Check Failed"
        }
    }

    var message: String {
        switch self {
        case .updateAvailable(let release):
            return "A newer version of Blink is available. View the release page to download and install \(release.tagName)."
        case .upToDate(let currentVersion):
            return "You’re already running Blink \(currentVersion)."
        case .failed:
            return "Blink couldn’t reach GitHub to check for updates right now."
        }
    }
}

@MainActor @Observable
final class UpdateChecker {
    var availableRelease: AppRelease?
    var presentedAlert: UpdateCheckAlert?
    var isChecking = false

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
        Task { await check(presentResult: false) }
    }

    func check() async {
        await check(presentResult: true)
    }

    func check(presentResult: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                if presentResult {
                    presentedAlert = .failed
                }
                return
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            let result = Self.resolveResult(for: release, currentVersion: currentVersion)
            switch result {
            case .updateAvailable(let release):
                availableRelease = release
            case .upToDate:
                availableRelease = nil
            case .failed:
                availableRelease = nil
            }

            if presentResult {
                presentedAlert = result
            }
        } catch {
            if presentResult {
                presentedAlert = .failed
            }
        }
    }

    func openReleasePage() {
        guard let release = availableRelease,
              let url = URL(string: release.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    func openReleasePage(for release: AppRelease) {
        guard let url = URL(string: release.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissAlert() {
        presentedAlert = nil
    }

    static func resolveResult(for release: AppRelease, currentVersion: String) -> UpdateCheckAlert {
        let latestVersion = String(release.tagName.trimmingPrefix("v"))
        if isNewer(latestVersion, than: currentVersion) {
            return .updateAvailable(release)
        }

        return .upToDate(currentVersion: currentVersion)
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
