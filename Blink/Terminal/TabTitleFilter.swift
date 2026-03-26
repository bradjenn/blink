import Foundation

/// Maps terminal title strings to user-friendly tab names.
/// Returns nil if the title shouldn't update the tab (e.g. basic shell commands).
enum TabTitleFilter {

    /// Known processes that should update the tab title.
    private static let processMap: [String: String] = [
        // AI / Dev tools
        "codex": "Codex",
        "claude": "Claude Code",
        "aider": "Aider",
        "cursor": "Cursor",

        // Editors
        "vim": "Vim",
        "nvim": "Neovim",
        "nano": "Nano",
        "emacs": "Emacs",
        "yazi": "Yazi",

        // Runtimes
        "node": "Node",
        "python": "Python",
        "python3": "Python",
        "ruby": "Ruby",
        "irb": "Ruby REPL",
        "bun": "Bun",

        // Package managers / build tools
        "npm": "npm",
        "pnpm": "pnpm",
        "yarn": "Yarn",
        "cargo": "Cargo",
        "make": "Make",
        "cmake": "CMake",
        "zig": "Zig",

        // Go
        "go": "Go",

        // Databases
        "psql": "PostgreSQL",
        "mysql": "MySQL",
        "sqlite3": "SQLite",
        "redis-cli": "Redis",

        // Infrastructure
        "docker": "Docker",
        "docker-compose": "Docker Compose",
        "kubectl": "kubectl",
        "terraform": "Terraform",

        // Network / Remote
        "ssh": "SSH",
        "curl": "curl",

        // System
        "htop": "System Monitor",
        "top": "System Monitor",
        "tmux": "tmux",

        // Pagers
        "less": "Less",
        "man": "Man",

        // Git (long-running only)
        "git log": "Git Log",
        "git diff": "Git Diff",
        "git rebase": "Git Rebase",
    ]

    /// Filter a terminal title. Returns a display name if the process should
    /// update the tab title, or nil if the title should be ignored.
    static func displayName(for title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Check for exact matches first (e.g. "htop", "nvim")
        if let name = processMap[trimmed] {
            return name
        }

        // Extract the first word as the process name
        let firstWord = String(trimmed.split(separator: " ").first ?? "")

        // Check the process name against the map
        if let name = processMap[firstWord] {
            // For SSH, include the target
            if firstWord == "ssh" {
                let parts = trimmed.split(separator: " ")
                if parts.count > 1 {
                    return "SSH: \(parts.dropFirst().joined(separator: " "))"
                }
            }
            return name
        }

        // Check for multi-word commands (e.g. "git log", "npm run")
        let twoWords = trimmed.split(separator: " ").prefix(2).joined(separator: " ")
        if let name = processMap[twoWords] {
            return name
        }

        // Not a known process — don't update tab title
        return nil
    }

    static func managedAIKind(for title: String) -> ManagedAIPaneKind? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let kind = ManagedAIPaneKind(command: trimmed) {
            return kind
        }

        let firstWord = String(trimmed.split(separator: " ").first ?? "")
        if let kind = ManagedAIPaneKind(command: firstWord) {
            return kind
        }

        return nil
    }

    /// Shell names that indicate the user is back at a prompt.
    private static let shellNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "csh", "tcsh", "ksh", "dash",
    ]

    /// Check if the title indicates a return to shell prompt.
    static func isShellPrompt(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let firstWord = String(trimmed.split(separator: " ").first ?? "")

        // Check if the first word is a shell name
        if shellNames.contains(firstWord) { return true }

        // Check if it ends with a shell name (e.g. "user@host: /path - zsh")
        if let lastWord = trimmed.split(separator: " ").last {
            if shellNames.contains(String(lastWord)) { return true }
        }

        // Check for common shell prompt patterns (contains path-like content)
        if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") { return true }

        return false
    }
}
