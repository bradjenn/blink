import Foundation

enum ClaudeTabActivityKind: String {
    case running
    case needsInput
    case completed
}

struct ClaudeTabActivity: Equatable {
    let kind: ClaudeTabActivityKind
    let summary: String?
    let updatedAt: Date
}

struct ClaudeHookEvent {
    let event: String
    let workspaceId: String
    let tabId: String
    let paneId: String?
    let workspacePath: String?
    let cwd: String?
    let pid: Int?
    let rawInput: String
}

final class ClaudeHookReceiver {
    let eventDirectoryURL: URL

    private let onEvent: @MainActor (ClaudeHookEvent) -> Void
    private let queue = DispatchQueue(label: "com.blink.claude-hooks")
    private var directoryFileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init?(bundleIdentifier: String, onEvent: @escaping @MainActor (ClaudeHookEvent) -> Void) {
        let sanitizedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let eventDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedBundleIdentifier)-claude-hooks", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: eventDirectoryURL,
                withIntermediateDirectories: true
            )
            if let existingFiles = try? FileManager.default.contentsOfDirectory(
                at: eventDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for fileURL in existingFiles where fileURL.pathExtension == "event" || fileURL.pathExtension == "tmp" {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            return nil
        }

        self.eventDirectoryURL = eventDirectoryURL
        self.onEvent = onEvent
        startWatching()
        drainPendingEvents()
    }

    deinit {
        source?.cancel()
    }

    private func startWatching() {
        directoryFileDescriptor = open((eventDirectoryURL.path as NSString).fileSystemRepresentation, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.drainPendingEvents()
        }
        source.setCancelHandler { [fd = directoryFileDescriptor] in
            if fd >= 0 {
                close(fd)
            }
        }
        self.source = source
        source.resume()
    }

    private func drainPendingEvents() {
        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: eventDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let eventFiles = fileURLs
            .filter { $0.pathExtension == "event" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate < rhsDate
            }

        for fileURL in eventFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let event = Self.parseEvent(content) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            try? fileManager.removeItem(at: fileURL)
            Task { @MainActor [onEvent] in
                onEvent(event)
            }
        }
    }

    private static func parseEvent(_ content: String) -> ClaudeHookEvent? {
        var fields: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex])
            let value = String(line[line.index(after: separatorIndex)...])
            fields[key] = value
        }

        let workspaceId = fields["workspace_id"] ?? fields["project_id"]
        let workspacePath = decodeBase64(fields["workspace_path_b64"] ?? fields["project_path_b64"])

        guard fields["kind"] == "claude-hook",
              let event = fields["event"], !event.isEmpty,
              let workspaceId, !workspaceId.isEmpty,
              let tabId = fields["tab_id"], !tabId.isEmpty else {
            return nil
        }

        return ClaudeHookEvent(
            event: event,
            workspaceId: workspaceId,
            tabId: tabId,
            paneId: fields["pane_id"],
            workspacePath: workspacePath,
            cwd: decodeBase64(fields["cwd_b64"]),
            pid: fields["pid"].flatMap(Int.init),
            rawInput: decodeBase64(fields["input_b64"]) ?? ""
        )
    }

    private static func decodeBase64(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

enum ClaudeHookScriptInstaller {
    static func install(bundleIdentifier: String) -> URL? {
        let sanitizedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedBundleIdentifier)-cli-bin", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try write(script: blinkHelperScript, named: "blink-helper", into: directoryURL)
            try write(script: claudeWrapperScript, named: "claude", into: directoryURL)
            return directoryURL
        } catch {
            return nil
        }
    }

    static func installShellIntegration(bundleIdentifier: String) -> URL? {
        let sanitizedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedBundleIdentifier)-shell-integration", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try write(script: zshBootstrapScript, named: ".zshenv", into: directoryURL)
            try write(script: zshProfileScript, named: ".zprofile", into: directoryURL)
            try write(script: zshRcScript, named: ".zshrc", into: directoryURL)
            try write(script: zshLoginScript, named: ".zlogin", into: directoryURL)
            try write(script: zshIntegrationScript, named: "blink-zsh-integration.zsh", into: directoryURL)
            return directoryURL
        } catch {
            return nil
        }
    }

    private static func write(script: String, named fileName: String, into directoryURL: URL) throws {
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8),
           existing == script {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            return
        }

        try script.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
    }

    private static let blinkHelperScript = #"""
#!/usr/bin/env bash
set -euo pipefail

encode_b64() {
    if [[ $# -eq 0 ]]; then
        base64 | tr -d '\n'
    else
        printf '%s' "$1" | base64 | tr -d '\n'
    fi
}

send_event() {
    local event="$1"
    local event_dir="${BLINK_HOOK_EVENT_DIR:-}"
    local tab_id="${BLINK_TAB_ID:-}"
    local pane_id="${BLINK_PANE_ID:-}"
    local workspace_id="${BLINK_PROJECT_ID:-}"

    [[ -n "$event_dir" && -d "$event_dir" && -n "$tab_id" && -n "$workspace_id" ]] || return 0

    local raw_input=""
    if [[ ! -t 0 ]]; then
        raw_input="$(cat || true)"
    fi

    local tmp_file="${event_dir}/claude-hook.$$.$RANDOM.tmp"
    local final_file="${event_dir}/claude-hook.$(date +%s).$$.$RANDOM.event"

    {
        printf 'kind=claude-hook\n'
        printf 'event=%s\n' "$event"
        printf 'workspace_id=%s\n' "$workspace_id"
        printf 'tab_id=%s\n' "$tab_id"
        printf 'pane_id=%s\n' "$pane_id"
        printf 'pid=%s\n' "${BLINK_CLAUDE_PID:-}"
        printf 'workspace_path_b64=%s\n' "$(encode_b64 "${BLINK_PROJECT_PATH:-}")"
        printf 'cwd_b64=%s\n' "$(encode_b64 "${PWD:-}")"
        printf 'input_b64=%s\n' "$(encode_b64 "$raw_input")"
    } > "$tmp_file"

    mv "$tmp_file" "$final_file"
}

case "${1:-}" in
    claude-hook)
        shift
        send_event "${1:-help}"
        ;;
    *)
        exit 0
        ;;
esac
"""#

    private static let claudeWrapperScript = #"""
#!/usr/bin/env bash
# Blink claude wrapper - injects workspace status and notifications.
set -euo pipefail

find_real_claude() {
    local self_dir
    self_dir="$(cd "$(dirname "$0")" && pwd)"
    local IFS=:
    for d in $PATH; do
        [[ "$d" == "$self_dir" ]] && continue
        [[ -x "$d/claude" ]] && printf '%s' "$d/claude" && return 0
    done
    return 1
}

in_blink_terminal() {
    [[ -n "${BLINK_TAB_ID:-}" && -n "${BLINK_PROJECT_ID:-}" ]]
}

hooks_available() {
    [[ -n "${BLINK_HOOK_EVENT_DIR:-}" && -d "${BLINK_HOOK_EVENT_DIR:-}" ]] || return 1
    local self_dir
    self_dir="$(cd "$(dirname "$0")" && pwd)"
    [[ -x "$self_dir/blink-helper" ]]
}

REAL_CLAUDE="$(find_real_claude)" || {
    echo "Error: claude not found in PATH" >&2
    exit 127
}

case "${1:-}" in
    mcp|config|api-key|rc|remote-control)
        exec "$REAL_CLAUDE" "$@"
        ;;
esac

if ! in_blink_terminal || [[ "${BLINK_CLAUDE_HOOKS_DISABLED:-0}" == "1" ]] || ! hooks_available; then
    unset CLAUDECODE
    exec "$REAL_CLAUDE" "$@"
fi

unset CLAUDECODE
export BLINK_CLAUDE_PID=$$
export BLINK_PROJECT_PATH="${BLINK_PROJECT_PATH:-$PWD}"
BLINK_HELPER="$(cd "$(dirname "$0")" && pwd)/blink-helper"

skip_session_id=false
for arg in "$@"; do
    case "$arg" in
        --resume|--resume=*|--session-id|--session-id=*|--continue|-c)
            skip_session_id=true
            break
            ;;
    esac
done

HOOKS_JSON="{\"hooks\":{\"SessionStart\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook session-start\",\"timeout\":10}]}],\"Stop\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook stop\",\"timeout\":10}]}],\"SessionEnd\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook session-end\",\"timeout\":2}]}],\"Notification\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook notification\",\"timeout\":10}]}],\"UserPromptSubmit\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook prompt-submit\",\"timeout\":10}]}],\"PreToolUse\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"$BLINK_HELPER claude-hook pre-tool-use\",\"timeout\":5,\"async\":true}]}]}}"

if [[ "$skip_session_id" == true ]]; then
    exec "$REAL_CLAUDE" --settings "$HOOKS_JSON" "$@"
else
    SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    exec "$REAL_CLAUDE" --session-id "$SESSION_ID" --settings "$HOOKS_JSON" "$@"
fi
"""#

    private static let zshBootstrapScript = #"""
# Blink ZDOTDIR bootstrap for zsh.
{
    builtin typeset _blink_original_zdotdir="${BLINK_ZSH_ZDOTDIR:-$HOME}"
    builtin typeset _blink_file="${_blink_original_zdotdir}/.zshenv"
    [[ ! -r "$_blink_file" ]] || builtin source -- "$_blink_file"
} always {
    builtin unset _blink_original_zdotdir _blink_file
}
"""#

    private static let zshProfileScript = #"""
# Blink ZDOTDIR wrapper for zsh profile.
{
    builtin typeset _blink_original_zdotdir="${BLINK_ZSH_ZDOTDIR:-$HOME}"
    builtin typeset _blink_file="${_blink_original_zdotdir}/.zprofile"
    [[ ! -r "$_blink_file" ]] || builtin source -- "$_blink_file"
} always {
    builtin unset _blink_original_zdotdir _blink_file
}
"""#

    private static let zshRcScript = #"""
# Blink ZDOTDIR wrapper for zsh rc.
{
    builtin typeset _blink_original_zdotdir="${BLINK_ZSH_ZDOTDIR:-$HOME}"
    builtin typeset _blink_file="${_blink_original_zdotdir}/.zshrc"
    [[ ! -r "$_blink_file" ]] || builtin source -- "$_blink_file"
} always {
    if [[ -o interactive && "${BLINK_SHELL_INTEGRATION:-1}" != "0" && -n "${BLINK_SHELL_INTEGRATION_DIR:-}" ]]; then
        builtin typeset _blink_integration="$BLINK_SHELL_INTEGRATION_DIR/blink-zsh-integration.zsh"
        [[ -r "$_blink_integration" ]] && builtin source -- "$_blink_integration"
    fi

    builtin unset _blink_original_zdotdir _blink_file _blink_integration
}
"""#

    private static let zshLoginScript = #"""
# Blink ZDOTDIR wrapper for zsh login.
{
    builtin typeset _blink_original_zdotdir="${BLINK_ZSH_ZDOTDIR:-$HOME}"
    builtin typeset _blink_file="${_blink_original_zdotdir}/.zlogin"
    [[ ! -r "$_blink_file" ]] || builtin source -- "$_blink_file"
} always {
    builtin unset _blink_original_zdotdir _blink_file
}
"""#

    private static let zshIntegrationScript = #"""
# Blink shell integration for zsh.
# Injected automatically. Do not source manually.

if [[ -n "${BLINK_CLAUDE_WRAPPER_PATH:-}" && -x "${BLINK_CLAUDE_WRAPPER_PATH}" ]]; then
    builtin typeset _blink_wrapper_dir="${BLINK_CLAUDE_WRAPPER_PATH:h}"
    case ":${PATH:-}:" in
        *":${_blink_wrapper_dir}:"*) ;;
        *) export PATH="${_blink_wrapper_dir}${PATH:+:$PATH}" ;;
    esac

    claude() {
        "${BLINK_CLAUDE_WRAPPER_PATH}" "$@"
    }
fi

if [[ -n "${BLINK_NVIM_WRAPPER_PATH:-}" && -x "${BLINK_NVIM_WRAPPER_PATH}" ]]; then
    nvim() {
        "${BLINK_NVIM_WRAPPER_PATH}" "$@"
    }
    export EDITOR="${BLINK_NVIM_WRAPPER_PATH}"
    export VISUAL="${BLINK_NVIM_WRAPPER_PATH}"
fi

if [[ -n "${BLINK_VIM_WRAPPER_PATH:-}" && -x "${BLINK_VIM_WRAPPER_PATH}" ]]; then
    vim() {
        "${BLINK_VIM_WRAPPER_PATH}" "$@"
    }
fi

unset _blink_wrapper_dir
"""#
}

struct ClaudeHookParsedInput {
    let rawInput: String
    let object: [String: Any]?
    let sessionId: String?
    let cwd: String?
    let transcriptPath: String?
}

enum ClaudeHookSummary {
    static func parse(rawInput: String) -> ClaudeHookParsedInput {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ClaudeHookParsedInput(
                rawInput: rawInput,
                object: nil,
                sessionId: nil,
                cwd: nil,
                transcriptPath: nil
            )
        }

        return ClaudeHookParsedInput(
            rawInput: rawInput,
            object: json,
            sessionId: extractSessionId(from: json),
            cwd: extractCWD(from: json),
            transcriptPath: firstString(in: json, keys: ["transcript_path", "transcriptPath"])
        )
    }

    static func completionSummary(from parsedInput: ClaudeHookParsedInput) -> (subtitle: String, body: String)? {
        let cwd = parsedInput.cwd
        let transcript = parsedInput.transcriptPath.flatMap(readTranscriptSummary(path:))

        if let lastAssistantMessage = transcript?.lastAssistantMessage {
            let subtitle = workspaceSubtitle(prefix: "Completed", cwd: cwd)
            return (subtitle, lastAssistantMessage)
        }

        guard let cwd else { return nil }
        let subtitle = workspaceSubtitle(prefix: "Completed", cwd: cwd)
        let workspaceName = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath).lastPathComponent
        let body = workspaceName.isEmpty ? "Claude session completed" : "Claude session completed in \(workspaceName)"
        return (subtitle, body)
    }

    static func notificationSummary(rawInput: String) -> (subtitle: String, body: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("Waiting", "Claude is waiting for your input")
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let normalized = normalizedSingleLine(trimmed)
            return classify(signal: normalized, message: normalized)
        }

        let nested = (json["notification"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? [:]
        let signal = [
            firstString(in: json, keys: ["event", "event_name", "hook_event_name", "type", "kind"]),
            firstString(in: json, keys: ["notification_type", "matcher", "reason"]),
            firstString(in: nested, keys: ["type", "kind", "reason"])
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let message = [
            firstString(in: json, keys: ["message", "body", "text", "prompt", "error", "description"]),
            firstString(in: nested, keys: ["message", "body", "text", "prompt", "error", "description"])
        ]
        .compactMap { $0 }
        .first ?? "Claude needs your input"

        var summary = classify(signal: signal, message: normalizedSingleLine(message))
        summary.body = truncate(summary.body, maxLength: 180)
        return summary
    }

    static func promptTitle(rawInput: String) -> String? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let nested = (json["prompt"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? [:]
            let candidate = [
                firstString(in: json, keys: ["prompt", "message", "text", "input"]),
                firstString(in: nested, keys: ["prompt", "message", "text", "input"])
            ]
            .compactMap { $0 }
            .first

            if let candidate {
                let normalized = normalizedSingleLine(candidate)
                return normalized.isEmpty ? nil : truncate(normalized, maxLength: 48)
            }
        }

        let normalized = normalizedSingleLine(trimmed)
        guard !normalized.isEmpty else { return nil }
        return truncate(normalized, maxLength: 48)
    }

    private struct TranscriptSummary {
        let lastAssistantMessage: String?
    }

    private static func readTranscriptSummary(path: String) -> TranscriptSummary? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expandedPath)),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var lastAssistantMessage: String?
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "assistant",
                  let text = extractMessageText(from: message),
                  !text.isEmpty else {
                continue
            }
            lastAssistantMessage = truncate(normalizedSingleLine(text), maxLength: 120)
        }

        guard lastAssistantMessage != nil else { return nil }
        return TranscriptSummary(lastAssistantMessage: lastAssistantMessage)
    }

    private static func extractMessageText(from message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let contentArray = message["content"] as? [[String: Any]] {
            let texts = contentArray.compactMap { block -> String? in
                guard (block["type"] as? String) == "text",
                      let text = block["text"] as? String else {
                    return nil
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let joined = texts.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func workspaceSubtitle(prefix: String, cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return prefix }
        let expanded = NSString(string: cwd).expandingTildeInPath
        let workspaceName = URL(fileURLWithPath: expanded).lastPathComponent
        return workspaceName.isEmpty ? prefix : "\(prefix) in \(workspaceName)"
    }

    private static func extractSessionId(from object: [String: Any]) -> String? {
        if let sessionId = firstString(in: object, keys: ["session_id", "sessionId"]) {
            return sessionId
        }
        if let notification = object["notification"] as? [String: Any],
           let sessionId = firstString(in: notification, keys: ["session_id", "sessionId"]) {
            return sessionId
        }
        if let data = object["data"] as? [String: Any],
           let sessionId = firstString(in: data, keys: ["session_id", "sessionId"]) {
            return sessionId
        }
        if let session = object["session"] as? [String: Any],
           let sessionId = firstString(in: session, keys: ["id", "session_id", "sessionId"]) {
            return sessionId
        }
        if let context = object["context"] as? [String: Any],
           let sessionId = firstString(in: context, keys: ["session_id", "sessionId"]) {
            return sessionId
        }
        return nil
    }

    private static func extractCWD(from object: [String: Any]) -> String? {
        let cwdKeys = ["cwd", "working_directory", "workingDirectory", "workspace_dir", "workspaceDir"]
        if let cwd = firstString(in: object, keys: cwdKeys) {
            return cwd
        }
        if let notification = object["notification"] as? [String: Any],
           let cwd = firstString(in: notification, keys: cwdKeys) {
            return cwd
        }
        if let data = object["data"] as? [String: Any],
           let cwd = firstString(in: data, keys: cwdKeys) {
            return cwd
        }
        if let context = object["context"] as? [String: Any],
           let cwd = firstString(in: context, keys: cwdKeys) {
            return cwd
        }
        return nil
    }

    private static func classify(signal: String, message: String) -> (subtitle: String, body: String) {
        let lowered = "\(signal) \(message)".lowercased()
        if lowered.contains("permission") || lowered.contains("approve") || lowered.contains("approval") {
            return ("Permission", message.isEmpty ? "Approval needed" : message)
        }
        if lowered.contains("error") || lowered.contains("failed") || lowered.contains("exception") {
            return ("Error", message.isEmpty ? "Claude reported an error" : message)
        }
        if lowered.contains("complet") || lowered.contains("finish") || lowered.contains("done") || lowered.contains("success") {
            return ("Completed", message.isEmpty ? "Task completed" : message)
        }
        if lowered.contains("idle") || lowered.contains("wait") || lowered.contains("input") {
            return ("Waiting", message.isEmpty ? "Waiting for input" : message)
        }
        if !message.isEmpty, message != "Claude needs your input" {
            return ("Attention", message)
        }
        return ("Attention", "Claude needs your attention")
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = object[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func normalizedSingleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: max(0, maxLength - 1))
        return String(value[..<endIndex]) + "…"
    }
}
