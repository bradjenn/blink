import Foundation

actor ClaudeCLIService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func sendTurn(
        projectPath: String,
        model: String,
        sessionId: String?,
        prompt: String
    ) async throws -> ChatTurnResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw ChatProviderError.invalidRequest("Message cannot be empty.")
        }

        let resolvedSessionId = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? sessionId!.trimmingCharacters(in: .whitespacesAndNewlines)
            : UUID().uuidString.lowercased()

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("blink-claude-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.txt", isDirectory: false)
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log", isDirectory: false)

        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        var arguments = [
            "claude",
            "-p",
            "--output-format", "text",
            "--permission-mode", "dontAsk",
            "--tools", "",
            "--session-id", resolvedSessionId
        ]

        if !model.isEmpty {
            arguments.insert(contentsOf: ["--model", model], at: 1)
        }

        arguments.append(trimmedPrompt)

        process.arguments = arguments

        do {
            try process.run()
        } catch {
            throw ChatProviderError.launchFailed(
                "Blink could not start the local claude CLI. Install Claude Code and ensure `claude` is on your PATH."
            )
        }

        process.waitUntilExit()

        let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        if process.terminationStatus != 0 {
            let failureMessage = firstNonEmpty(
                stderrText,
                stdoutText,
                "The claude CLI failed while handling this message."
            )
            throw ChatProviderError.executionFailed(failureMessage)
        }

        let trimmedOutput = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            let failureMessage = firstNonEmpty(
                stderrText,
                "The claude CLI completed without returning an assistant message."
            )
            throw ChatProviderError.invalidResponse(failureMessage)
        }

        return ChatTurnResult(sessionId: resolvedSessionId, text: trimmedOutput)
    }

    private func firstNonEmpty(_ candidates: String...) -> String {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}
