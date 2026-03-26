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
        prompt: String,
        effort: String? = nil,
        permissionLevel: PermissionLevel = .readOnly,
        attachments: [ChatAttachment] = []
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
        let sharedArguments = codexArguments(
            model: model,
            effort: effort,
            permissionLevel: permissionLevel,
            attachments: attachments
        )

        if let sessionId, !sessionId.isEmpty {
            arguments.append("resume")
            arguments.append(contentsOf: sharedArguments)
            arguments.append("--json")
            arguments.append("--output-last-message")
            arguments.append(messageURL.path)
            arguments.append(sessionId)
            arguments.append("-")
        } else {
            arguments.append(contentsOf: sharedArguments)
            arguments.append("--json")
            arguments.append("--output-last-message")
            arguments.append(messageURL.path)
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

        return ChatTurnResult(
            sessionId: resolvedSessionId,
            text: resolvedMessage,
            runtimeEvents: parsed.runtimeEvents
        )
    }

    private func codexArguments(
        model: String,
        effort: String?,
        permissionLevel: PermissionLevel,
        attachments: [ChatAttachment]
    ) -> [String] {
        var arguments: [String] = []

        if !model.isEmpty {
            arguments.append(contentsOf: ["-m", model])
        }

        if let effort, !effort.isEmpty {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\(quotedConfigValue(effort))"])
        }

        let imageAttachments = attachments.filter(\.isImage)
        for attachment in imageAttachments {
            arguments.append(contentsOf: ["-i", attachment.path])
        }

        switch permissionLevel {
        case .readOnly:
            arguments.append(contentsOf: ["-c", "sandbox_mode=\(quotedConfigValue("read-only"))"])
            arguments.append(contentsOf: ["-c", "approval_policy=\(quotedConfigValue("never"))"])
        case .workspaceWrite:
            arguments.append(contentsOf: ["-c", "sandbox_mode=\(quotedConfigValue("workspace-write"))"])
            arguments.append(contentsOf: ["-c", "approval_policy=\(quotedConfigValue("never"))"])
        case .fullAccess:
            arguments.append("--dangerously-bypass-approvals-and-sandbox")
        }

        return arguments
    }

    private func parseEvents(from text: String) -> (
        threadId: String?,
        lastAssistantMessage: String,
        runtimeEvents: [ChatTurnRuntimeEvent]
    ) {
        var threadId: String?
        var lastAssistantMessage = ""
        var runtimeEvents: [ChatTurnRuntimeEvent] = []

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

            if type == "turn.plan.updated",
               let event = parsePlanUpdate(from: payload) {
                runtimeEvents.append(event)
                continue
            }

            if type == "turn.diff.updated",
               let event = parseDiffUpdate(from: payload) {
                runtimeEvents.append(event)
                continue
            }

            if type == "request.opened",
               let event = parseRequestOpened(from: payload) {
                runtimeEvents.append(event)
                continue
            }

            if type == "user-input.requested",
               let event = parseUserInputRequest(from: payload) {
                runtimeEvents.append(event)
                continue
            }

            guard type == "item.completed",
                  let item = payload["item"] as? [String: Any],
                  let itemType = item["type"] as? String else {
                continue
            }

            if itemType == "command_execution",
               let event = parseCommandEvent(from: item) {
                runtimeEvents.append(event)
                continue
            }

            if let event = parseSemanticEvent(from: item, itemType: itemType) {
                runtimeEvents.append(event)
                continue
            }

            guard itemType == "agent_message",
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            lastAssistantMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (threadId, lastAssistantMessage, runtimeEvents)
    }

    private func parseCommandEvent(from item: [String: Any]) -> ChatTurnRuntimeEvent? {
        let detail = commandDetail(from: item)
        let output = firstNonEmptyString(
            item["aggregated_output"],
            item["output"],
            item["stderr"],
            item["stdout"]
        )
        let exitCode = item["exit_code"] as? Int
        let status = resolvedStatus(from: item["status"] as? String, exitCode: exitCode)

        guard detail != nil || output != nil else {
            return nil
        }

        let identifier = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatTurnRuntimeEvent(
            id: identifier?.isEmpty == false ? identifier! : UUID().uuidString,
            kind: .commandExecution,
            title: "Ran command",
            detail: detail,
            output: output?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: runtimeStatus(for: status),
            exitCode: exitCode,
            requestId: nil,
            questions: [],
            changedFiles: []
        )
    }

    private func parseSemanticEvent(
        from item: [String: Any],
        itemType: String
    ) -> ChatTurnRuntimeEvent? {
        let normalizedType = itemType
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .lowercased()
        let kind: ChatRuntimeEventKind
        let title: String

        if normalizedType.contains("reasoning") || normalizedType.contains("thought") {
            kind = .reasoning
            title = "Reasoning"
        } else if normalizedType.contains("plan") || normalizedType.contains("todo") {
            kind = .planUpdate
            title = "Plan updated"
        } else {
            return nil
        }

        let detail = firstNonEmptyString(
            item["summary"],
            item["text"],
            item["title"]
        )
        let identifier = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard detail != nil else {
            return nil
        }

        return ChatTurnRuntimeEvent(
            id: identifier?.isEmpty == false ? identifier! : UUID().uuidString,
            kind: kind,
            title: title,
            detail: detail,
            output: nil,
            status: .completed,
            exitCode: nil,
            requestId: nil,
            questions: [],
            changedFiles: []
        )
    }

    private func parsePlanUpdate(from payload: [String: Any]) -> ChatTurnRuntimeEvent? {
        let explanation = firstNonEmptyString(payload["explanation"])
        let steps = (payload["plan"] as? [[String: Any]] ?? [])
            .compactMap { entry -> String? in
                guard let step = firstNonEmptyString(entry["step"]) else {
                    return nil
                }

                let status = (entry["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let status, !status.isEmpty {
                    return "[\(status)] \(step)"
                }

                return step
            }
            .joined(separator: "\n")

        let output = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard explanation != nil || !output.isEmpty else {
            return nil
        }

        return ChatTurnRuntimeEvent(
            id: UUID().uuidString,
            kind: .planUpdate,
            title: "Plan updated",
            detail: explanation,
            output: output.isEmpty ? nil : output,
            status: .completed,
            exitCode: nil,
            requestId: nil,
            questions: [],
            changedFiles: []
        )
    }

    private func parseDiffUpdate(from payload: [String: Any]) -> ChatTurnRuntimeEvent? {
        let diffText = firstNonEmptyString(payload["diff"], payload["summary"])
        let changedFiles = diffFiles(from: payload)

        guard diffText != nil || !changedFiles.isEmpty else {
            return nil
        }

        return ChatTurnRuntimeEvent(
            id: UUID().uuidString,
            kind: .diffUpdate,
            title: "Diff updated",
            detail: diffText,
            output: nil,
            status: .completed,
            exitCode: nil,
            requestId: nil,
            questions: [],
            changedFiles: changedFiles
        )
    }

    private func parseRequestOpened(from payload: [String: Any]) -> ChatTurnRuntimeEvent? {
        let requestId = firstNonEmptyString(payload["request_id"], payload["id"])
        let detail = firstNonEmptyString(payload["detail"], payload["summary"], payload["title"])
        let rawType = firstNonEmptyString(payload["request_type"], payload["type"])

        let title = rawType?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "Approval requested"

        guard requestId != nil || detail != nil else {
            return nil
        }

        return ChatTurnRuntimeEvent(
            id: requestId ?? UUID().uuidString,
            kind: .approvalRequest,
            title: title,
            detail: detail,
            output: nil,
            status: .pending,
            exitCode: nil,
            requestId: requestId,
            questions: [],
            changedFiles: []
        )
    }

    private func parseUserInputRequest(from payload: [String: Any]) -> ChatTurnRuntimeEvent? {
        let requestId = firstNonEmptyString(payload["request_id"], payload["id"])
        let questions = (payload["questions"] as? [[String: Any]] ?? []).compactMap(parseQuestion)
        let detail = firstNonEmptyString(payload["detail"], payload["summary"], payload["prompt"])

        guard !questions.isEmpty || detail != nil else {
            return nil
        }

        return ChatTurnRuntimeEvent(
            id: requestId ?? UUID().uuidString,
            kind: .userInputRequest,
            title: "Input requested",
            detail: detail,
            output: nil,
            status: .pending,
            exitCode: nil,
            requestId: requestId,
            questions: questions,
            changedFiles: []
        )
    }

    private func commandDetail(from item: [String: Any]) -> String? {
        if let command = item["command"] as? String {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let commandParts = item["command"] as? [String] {
            let rendered = commandParts
                .map(shellRenderedArgument)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rendered.isEmpty ? nil : rendered
        }

        return nil
    }

    private func shellRenderedArgument(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func resolvedStatus(from rawValue: String?, exitCode: Int?) -> ChatWorkItemStatus {
        switch rawValue?.lowercased() {
        case "completed", "success":
            return (exitCode ?? 0) == 0 ? .completed : .failed
        case "failed", "error":
            return .failed
        default:
            if let exitCode, exitCode != 0 {
                return .failed
            }
            return .completed
        }
    }

    private func runtimeStatus(for status: ChatWorkItemStatus) -> ChatRuntimeEventStatus {
        switch status {
        case .inProgress:
            .inProgress
        case .completed:
            .completed
        case .failed:
            .failed
        }
    }

    private func diffFiles(from payload: [String: Any]) -> [ChatRuntimeDiffFile] {
        (payload["files"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let path = firstNonEmptyString(entry["path"], entry["file"]) else {
                return nil
            }

            return ChatRuntimeDiffFile(
                path: path,
                additions: entry["additions"] as? Int,
                deletions: entry["deletions"] as? Int
            )
        }
    }

    private func parseQuestion(from payload: [String: Any]) -> ChatRuntimeQuestion? {
        guard let id = firstNonEmptyString(payload["id"]),
              let header = firstNonEmptyString(payload["header"]) else {
            return nil
        }

        let prompt = firstNonEmptyString(payload["question"], payload["prompt"]) ?? header
        let options: [ChatRuntimeQuestionOption] = (payload["options"] as? [[String: Any]] ?? []).compactMap { option in
            guard let label = firstNonEmptyString(option["label"]) else {
                return nil
            }

            return ChatRuntimeQuestionOption(
                id: firstNonEmptyString(option["id"]) ?? UUID().uuidString,
                label: label,
                description: firstNonEmptyString(option["description"])
            )
        }

        return ChatRuntimeQuestion(id: id, header: header, prompt: prompt, options: options)
    }

    private func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
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

    private func quotedConfigValue(_ value: String) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedValue)\""
    }
}
