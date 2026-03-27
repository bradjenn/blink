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
        prompt: String,
        effort: String? = nil,
        permissionLevel: PermissionLevel = .readOnly,
        attachments: [ChatAttachment] = []
    ) async throws -> ChatTurnResult {
        try await sendTurn(
            projectPath: projectPath,
            model: model,
            sessionId: sessionId,
            prompt: prompt,
            effort: effort,
            permissionLevel: permissionLevel,
            attachments: attachments,
            allowSessionReset: true
        )
    }

    private func sendTurn(
        projectPath: String,
        model: String,
        sessionId: String?,
        prompt: String,
        effort: String? = nil,
        permissionLevel: PermissionLevel = .readOnly,
        attachments: [ChatAttachment] = [],
        allowSessionReset: Bool
    ) async throws -> ChatTurnResult {
        let attachmentContext = attachmentPromptContext(for: attachments)
        let effectivePrompt = [attachmentContext, prompt]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = effectivePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard let executableURL = await LocalCLIResolver.shared.executableURL(named: "claude") else {
            throw ChatProviderError.launchFailed(
                "Blink could not find the local claude CLI from the app environment or your login shell. Install Claude Code and ensure `claude` is on your PATH."
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.environment = await LocalCLIResolver.shared.launchEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        var arguments: [String] = []

        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }

        if let effort, !effort.isEmpty {
            arguments.append(contentsOf: ["--effort", effort])
        }

        arguments.append(contentsOf: ["-p", "--output-format", "text"])

        switch permissionLevel {
        case .readOnly:
            arguments.append(contentsOf: ["--permission-mode", "dontAsk", "--tools", ""])
        case .workspaceWrite:
            arguments.append(contentsOf: ["--permission-mode", "acceptEdits", "--tools", "default"])
        case .fullAccess:
            arguments.append(contentsOf: [
                "--permission-mode", "bypassPermissions",
                "--dangerously-skip-permissions",
                "--tools", "default"
            ])
        }

        arguments.append(contentsOf: ["--session-id", resolvedSessionId])

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
            if allowSessionReset,
               sessionId != nil,
               indicatesBusySession(stderr: stderrText, stdout: stdoutText) {
                return try await sendTurn(
                    projectPath: projectPath,
                    model: model,
                    sessionId: nil,
                    prompt: prompt,
                    effort: effort,
                    permissionLevel: permissionLevel,
                    attachments: attachments,
                    allowSessionReset: false
                )
            }

            let failureMessage = ChatCLITroubleshooting.failureMessage(
                providerName: "Claude Code",
                command: "claude",
                stderr: stderrText,
                stdout: stdoutText,
                fallback: "The claude CLI failed while handling this message."
            )
            throw ChatProviderError.executionFailed(failureMessage)
        }

        let trimmedOutput = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            let failureMessage = ChatCLITroubleshooting.emptyResponseMessage(
                providerName: "Claude Code",
                command: "claude",
                stderr: stderrText,
                fallback: "The claude CLI completed without returning an assistant message."
            )
            throw ChatProviderError.invalidResponse(failureMessage)
        }

        return ChatTurnResult(sessionId: resolvedSessionId, text: trimmedOutput)
    }

    private func indicatesBusySession(stderr: String, stdout: String) -> Bool {
        let combined = "\(stderr)\n\(stdout)".lowercased()
        return combined.contains("session id")
            && combined.contains("already in use")
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

    private func attachmentPromptContext(for attachments: [ChatAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }

        let lines = attachments.map { attachment in
            let kind = attachment.isImage ? "image" : "file"
            return "- \(attachment.name) (\(kind)) at \(attachment.path)"
        }

        return """
        Attached context:
        \(lines.joined(separator: "\n"))

        Use these workspace files as part of the request when relevant.
        """
    }
}
