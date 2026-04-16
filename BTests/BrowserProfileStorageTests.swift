import XCTest
@testable import Blink

final class BrowserProfileStorageTests: XCTestCase {
    func testCleanupOrphanedStorageRemovesLegacyProfileDirectoriesOnly() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("blink-browser-storage-\(UUID().uuidString)", isDirectory: true)
        let bundleIdentifier = "com.blink.tests"
        let appSupportRoot = root
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Blink", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Chromium", isDirectory: true)
        let cachesRoot = root
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("Blink", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Chromium", isDirectory: true)

        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cachesRoot, withIntermediateDirectories: true)

        let activeProfileId = "blink-profile-personal"
        try createProfileDirectory(named: activeProfileId, in: appSupportRoot)
        try createProfileDirectory(named: UUID().uuidString, in: appSupportRoot)
        try createProfileDirectory(named: UUID().uuidString, in: cachesRoot)
        try createDirectory(named: "component_crx_cache", in: appSupportRoot)
        try createDirectory(named: ".\(bundleIdentifier).stale", in: appSupportRoot)

        BrowserProfileStorage.cleanupOrphanedStorage(
            activeProfileIds: [activeProfileId],
            roots: [appSupportRoot, cachesRoot],
            bundleIdentifier: bundleIdentifier,
            fileManager: fileManager
        )

        XCTAssertTrue(fileManager.fileExists(atPath: appSupportRoot.appendingPathComponent(activeProfileId).path))
        XCTAssertTrue(fileManager.fileExists(atPath: appSupportRoot.appendingPathComponent("component_crx_cache").path))
        XCTAssertFalse(try fileManager.contentsOfDirectory(atPath: appSupportRoot.path).contains(where: { UUID(uuidString: $0) != nil }))
        XCTAssertFalse(fileManager.fileExists(atPath: appSupportRoot.appendingPathComponent(".\(bundleIdentifier).stale").path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: cachesRoot.path).filter { UUID(uuidString: $0) != nil }.count, 0)
    }

    func testRemoveStorageDeletesCurrentAndLegacyProfileDirectories() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("blink-browser-storage-remove-\(UUID().uuidString)", isDirectory: true)
        let appSupportRoot = root
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Blink", isDirectory: true)
            .appendingPathComponent("com.blink.tests", isDirectory: true)
            .appendingPathComponent("Chromium", isDirectory: true)
        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)

        let profileId = UUID().uuidString
        try createProfileDirectory(named: profileId, in: appSupportRoot)
        let legacyRoot = appSupportRoot.appendingPathComponent("profiles", isDirectory: true)
        try fileManager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try createProfileDirectory(named: profileId, in: legacyRoot)

        BrowserProfileStorage.removeStorage(
            for: profileId,
            roots: [appSupportRoot],
            fileManager: fileManager
        )

        XCTAssertFalse(fileManager.fileExists(atPath: appSupportRoot.appendingPathComponent(profileId).path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyRoot.appendingPathComponent(profileId).path))
    }

    private func createProfileDirectory(named name: String, in root: URL) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferencesURL = directory.appendingPathComponent("Preferences", isDirectory: false)
        _ = FileManager.default.createFile(atPath: preferencesURL.path, contents: Data())
    }

    private func createDirectory(named name: String, in root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}
