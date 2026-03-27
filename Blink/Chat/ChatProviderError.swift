import Foundation

enum ChatProviderError: LocalizedError {
    case invalidRequest(String)
    case launchFailed(String)
    case executionFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message),
             .launchFailed(let message),
             .executionFailed(let message),
             .invalidResponse(let message):
            return message
        }
    }
}

struct CLIAvailabilityStatus: Equatable {
    let command: String
    let executableURL: URL?
    let path: String

    var isAvailable: Bool {
        executableURL != nil
    }
}

actor LocalCLIResolver {
    static let shared = LocalCLIResolver()

    private let fileManager = FileManager.default
    private var cachedPATH: String?
    private var cachedExecutables: [String: URL] = [:]

    private static let fallbackHomeRelativePATHEntries = [
        ".local/bin",
        "bin",
        ".cargo/bin",
    ]

    private static let fallbackSystemPATHEntries = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    func refresh() {
        cachedPATH = nil
        cachedExecutables.removeAll()
    }

    func launchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = resolvedPATH()
        return environment
    }

    func executableURL(named command: String) -> URL? {
        if let cached = cachedExecutables[command] {
            return cached
        }

        guard let executablePath = findExecutablePath(named: command, in: resolvedPATH()) else {
            return nil
        }

        let url = URL(fileURLWithPath: executablePath)
        cachedExecutables[command] = url
        return url
    }

    func status(for command: String) -> CLIAvailabilityStatus {
        CLIAvailabilityStatus(
            command: command,
            executableURL: executableURL(named: command),
            path: resolvedPATH()
        )
    }

    private func resolvedPATH() -> String {
        if let cachedPATH {
            return cachedPATH
        }

        let resolved = loginShellPATH() ?? fallbackPATH()
        cachedPATH = resolved
        return resolved
    }

    private func loginShellPATH() -> String? {
        let shellPath = UserDefaults.standard.string(forKey: "blink.shell")
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", "printf %s \"$PATH\""]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return path.isEmpty ? nil : path
    }

    private func fallbackPATH() -> String {
        var entries: [String] = []
        var seen = Set<String>()

        func append(_ entry: String?) {
            guard let raw = entry?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !seen.contains(raw) else { return }
            seen.insert(raw)
            entries.append(raw)
        }

        let home = NSHomeDirectory()
        for relativePath in Self.fallbackHomeRelativePATHEntries {
            append((home as NSString).appendingPathComponent(relativePath))
        }

        if let inheritedPATH = ProcessInfo.processInfo.environment["PATH"] {
            for entry in inheritedPATH.split(separator: ":") {
                append(String(entry))
            }
        }

        for entry in Self.fallbackSystemPATHEntries {
            append(entry)
        }

        return entries.joined(separator: ":")
    }

    private func findExecutablePath(named command: String, in path: String) -> String? {
        for entry in path.split(separator: ":") {
            let directory = String(entry)
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

enum ChatCLITroubleshooting {
    static func failureMessage(
        providerName: String,
        command: String,
        stderr: String,
        stdout: String,
        fallback: String
    ) -> String {
        let combined = [stderr, stdout]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = combined.lowercased()

        if containsAny(
            in: normalized,
            needles: [
                "not authenticated",
                "authentication",
                "api key",
                "login required",
                "log in",
                "sign in",
                "session expired",
                "invalid_api_key",
                "missing api key",
            ]
        ) {
            return "Blink found \(providerName), but it looks unauthenticated. Open Terminal and finish the \(command) login flow, then try again."
        }

        if containsAny(
            in: normalized,
            needles: [
                "unknown option",
                "unrecognized option",
                "unexpected argument",
                "unsupported option",
                "invalid option",
            ]
        ) {
            return "Blink found \(providerName), but the installed CLI looks incompatible with this chat integration. Update `\(command)` and try again."
        }

        if !combined.isEmpty {
            return combined
        }

        return fallback
    }

    static func emptyResponseMessage(
        providerName: String,
        command: String,
        stderr: String,
        fallback: String
    ) -> String {
        let normalized = stderr.lowercased()

        if containsAny(
            in: normalized,
            needles: [
                "not authenticated",
                "authentication",
                "api key",
                "login required",
                "log in",
                "sign in",
            ]
        ) {
            return "Blink found \(providerName), but it still needs authentication. Open Terminal, run `\(command)`, complete setup, then retry."
        }

        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return fallback
    }

    private static func containsAny(in text: String, needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
