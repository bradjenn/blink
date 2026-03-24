import Foundation

actor CodexCLIService {
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

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("blink-codex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.jsonl", isDirectory: false)
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log", isDirectory: false)
        let messageURL = tempDirectory.appendingPathComponent("last-message.txt", isDirectory: false)

        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        fileManager.createFile(atPath: messageURL.path, contents: nil)

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

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        var arguments = ["codex", "exec"]
        if let sessionId, !sessionId.isEmpty {
            arguments.append("resume")
            arguments.append("--json")
            arguments.append("--output-last-message")
            arguments.append(messageURL.path)
            if !model.isEmpty {
                arguments.append(contentsOf: ["-m", model])
            }
            arguments.append(sessionId)
            arguments.append("-")
        } else {
            arguments.append("--json")
            arguments.append("--output-last-message")
            arguments.append(messageURL.path)
            if !model.isEmpty {
                arguments.append(contentsOf: ["-m", model])
            }
            arguments.append(contentsOf: ["-C", projectPath, "-"])
        }
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            throw ChatProviderError.launchFailed(
                "Blink could not start the local codex CLI. Install Codex and ensure `codex` is on your PATH."
            )
        }

        if let promptData = "\(trimmedPrompt)\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(promptData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutText = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderrText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        let lastMessage = ((try? String(contentsOf: messageURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parsed = parseEvents(from: stdoutText)
        let resolvedSessionId = parsed.threadId ?? sessionId
        let resolvedMessage = lastMessage.isEmpty ? parsed.lastAssistantMessage : lastMessage

        if process.terminationStatus != 0 {
            let failureMessage = firstNonEmpty(
                stderrText,
                parsed.lastAssistantMessage,
                "The codex CLI failed while handling this message."
            )
            throw ChatProviderError.executionFailed(failureMessage)
        }

        guard let resolvedSessionId, !resolvedSessionId.isEmpty else {
            throw ChatProviderError.invalidResponse("The codex CLI did not return a session id.")
        }

        guard !resolvedMessage.isEmpty else {
            let failureMessage = firstNonEmpty(
                parsed.lastAssistantMessage,
                stderrText,
                "The codex CLI completed without returning an assistant message."
            )
            throw ChatProviderError.invalidResponse(failureMessage)
        }

        return ChatTurnResult(sessionId: resolvedSessionId, text: resolvedMessage)
    }

    private func parseEvents(from text: String) -> (threadId: String?, lastAssistantMessage: String) {
        var threadId: String?
        var lastAssistantMessage = ""

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = payload["type"] as? String else {
                continue
            }

            if type == "thread.started",
               let candidate = payload["thread_id"] as? String,
               !candidate.isEmpty {
                threadId = candidate
                continue
            }

            guard type == "item.completed",
                  let item = payload["item"] as? [String: Any],
                  let itemType = item["type"] as? String,
                  itemType == "agent_message",
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            lastAssistantMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (threadId, lastAssistantMessage)
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
