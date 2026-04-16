import Foundation

enum BrowserProfileStorage {
    private static let containerDirectoryName = "Blink"
    private static let chromiumDirectoryName = "Chromium"
    private static let defaultProfileDirectoryName = "Default"
    private static let profileMarkerNames: Set<String> = [
        "Cache",
        "Code Cache",
        "Cookies",
        "Cookies-journal",
        "History",
        "History-journal",
        "IndexedDB",
        "Local Storage",
        "Network",
        "Preferences",
        "Session Storage",
        "Visited Links",
    ]

    static func sanitizeProfileIdentifier(_ profileIdentifier: String) -> String {
        guard !profileIdentifier.isEmpty else {
            return "profile"
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let scalars = profileIdentifier.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "profile" : sanitized
    }

    static func cleanupOrphanedStorage(
        activeProfileIds: [String],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.blink.app",
        fileManager: FileManager = .default
    ) {
        cleanupOrphanedStorage(
            activeProfileIds: activeProfileIds,
            roots: [
                rootURL(for: .applicationSupportDirectory, bundleIdentifier: bundleIdentifier, fileManager: fileManager),
                rootURL(for: .cachesDirectory, bundleIdentifier: bundleIdentifier, fileManager: fileManager),
            ].compactMap { $0 },
            bundleIdentifier: bundleIdentifier,
            fileManager: fileManager
        )
    }

    static func removeStorage(
        for profileId: String,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.blink.app",
        fileManager: FileManager = .default
    ) {
        removeStorage(
            for: profileId,
            roots: [
                rootURL(for: .applicationSupportDirectory, bundleIdentifier: bundleIdentifier, fileManager: fileManager),
                rootURL(for: .cachesDirectory, bundleIdentifier: bundleIdentifier, fileManager: fileManager),
            ].compactMap { $0 },
            fileManager: fileManager
        )
    }

    static func cleanupOrphanedStorage(
        activeProfileIds: [String],
        roots: [URL],
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) {
        let activeDirectoryNames = Set(activeProfileIds.map(sanitizeProfileIdentifier(_:)))
            .union([defaultProfileDirectoryName])

        for rootURL in roots {
            cleanupRoot(
                rootURL,
                activeDirectoryNames: activeDirectoryNames,
                bundleIdentifier: bundleIdentifier,
                fileManager: fileManager
            )
        }
    }

    static func removeStorage(
        for profileId: String,
        roots: [URL],
        fileManager: FileManager = .default
    ) {
        let sanitizedProfileId = sanitizeProfileIdentifier(profileId)
        for rootURL in roots {
            let directProfileURL = rootURL.appendingPathComponent(sanitizedProfileId, isDirectory: true)
            try? fileManager.removeItem(at: directProfileURL)

            let legacyProfileURL = rootURL
                .appendingPathComponent("profiles", isDirectory: true)
                .appendingPathComponent(sanitizedProfileId, isDirectory: true)
            try? fileManager.removeItem(at: legacyProfileURL)
        }
    }

    private static func cleanupRoot(
        _ rootURL: URL?,
        activeDirectoryNames: Set<String>,
        bundleIdentifier: String,
        fileManager: FileManager
    ) {
        guard let rootURL,
              let children = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for childURL in children {
            guard isDirectory(childURL, fileManager: fileManager) else { continue }

            let directoryName = childURL.lastPathComponent
            if activeDirectoryNames.contains(directoryName) {
                continue
            }

            if isStaleTemporaryDirectory(directoryName, bundleIdentifier: bundleIdentifier) ||
                isLikelyProfileDirectory(childURL, fileManager: fileManager) {
                try? fileManager.removeItem(at: childURL)
            }
        }

        // Clean hidden Chromium temp directories as well.
        guard let hiddenChildren = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return
        }

        for childURL in hiddenChildren {
            guard isDirectory(childURL, fileManager: fileManager) else { continue }
            let directoryName = childURL.lastPathComponent
            guard isStaleTemporaryDirectory(directoryName, bundleIdentifier: bundleIdentifier) else { continue }
            try? fileManager.removeItem(at: childURL)
        }
    }

    private static func rootURL(
        for directory: FileManager.SearchPathDirectory,
        bundleIdentifier: String,
        fileManager: FileManager
    ) -> URL? {
        guard let baseURL = fileManager.urls(for: directory, in: .userDomainMask).first else {
            return nil
        }

        return baseURL
            .appendingPathComponent(containerDirectoryName, isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(chromiumDirectoryName, isDirectory: true)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func isLikelyProfileDirectory(_ directoryURL: URL, fileManager: FileManager) -> Bool {
        let directoryName = directoryURL.lastPathComponent
        if directoryName == defaultProfileDirectoryName {
            return false
        }

        if isProfileLikeName(directoryName) {
            return true
        }

        for markerName in profileMarkerNames {
            let markerURL = directoryURL.appendingPathComponent(markerName, isDirectory: false)
            if fileManager.fileExists(atPath: markerURL.path) {
                return true
            }
        }

        return false
    }

    private static func isProfileLikeName(_ directoryName: String) -> Bool {
        UUID(uuidString: directoryName) != nil ||
            directoryName.hasPrefix("blink-profile-") ||
            directoryName == "blink-scratch-space"
    }

    private static func isStaleTemporaryDirectory(_ directoryName: String, bundleIdentifier: String) -> Bool {
        directoryName.hasPrefix(".\(bundleIdentifier).")
    }
}
