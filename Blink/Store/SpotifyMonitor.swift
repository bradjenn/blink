import AppKit
import Foundation

struct SpotifyStatus: Equatable {
    let track: String
    let artist: String
    let album: String
    let artworkURL: String?
    let isPlaying: Bool

    var hasTrack: Bool { !track.isEmpty }

    static let empty = SpotifyStatus(track: "", artist: "", album: "", artworkURL: nil, isPlaying: false)
}

@MainActor @Observable
final class SpotifyMonitor {
    private static let pausedVisibilityDuration: TimeInterval = 20

    var status: SpotifyStatus = .empty
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var hasSeenPlaybackThisSession = false
    private var pausedStatus: SpotifyStatus?
    private var pauseStartedAt: Date?

    func startMonitoring(performInitialRefresh: Bool = true) {
        stopMonitoring()
        if performInitialRefresh {
            refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        timer?.invalidate()
        timer = nil
        hasSeenPlaybackThisSession = false
        pausedStatus = nil
        pauseStartedAt = nil
        status = .empty
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let newStatus = await Task.detached(priority: .utility) {
                fetchSpotifyStatus()
            }.value
            guard !Task.isCancelled else { return }
            self.applyStatus(newStatus)
        }
    }

    private func applyStatus(_ newStatus: SpotifyStatus) {
        guard newStatus.hasTrack else {
            pausedStatus = nil
            pauseStartedAt = nil
            status = .empty
            return
        }

        guard !newStatus.isPlaying else {
            hasSeenPlaybackThisSession = true
            pausedStatus = nil
            pauseStartedAt = nil
            status = newStatus
            return
        }

        guard hasSeenPlaybackThisSession else {
            status = .empty
            return
        }

        if pausedStatus != newStatus {
            pausedStatus = newStatus
            pauseStartedAt = Date()
        }

        guard let pauseStartedAt,
              Date().timeIntervalSince(pauseStartedAt) < Self.pausedVisibilityDuration else {
            status = .empty
            return
        }

        status = newStatus
    }
}

private func fetchSpotifyStatus() -> SpotifyStatus {
    guard isSpotifyRunning() else { return .empty }

    // Query track info in a single script to minimize process spawns
    let script = """
    tell application "Spotify"
        if player state is stopped then return "STOPPED"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackArtwork to artwork url of current track
        set pState to player state as string
        return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & trackArtwork & "||" & pState
    end tell
    """
    let result = runOsascript(script: script).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.isEmpty, result != "STOPPED" else { return .empty }

    let parts = result.components(separatedBy: "||")
    guard parts.count >= 5 else { return .empty }

    return SpotifyStatus(
        track: parts[0],
        artist: parts[1],
        album: parts[2],
        artworkURL: parts[3].isEmpty ? nil : parts[3],
        isPlaying: parts[4] == "playing"
    )
}

private func isSpotifyRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
}

private func runOsascript(script: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        return ""
    }
}
