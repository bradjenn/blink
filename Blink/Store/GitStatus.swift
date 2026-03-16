import Foundation

struct GitStatus: Equatable {
    let branch: String
    let added: Int
    let modified: Int
    let deleted: Int

    var hasChanges: Bool { added > 0 || modified > 0 || deleted > 0 }

    static let empty = GitStatus(branch: "", added: 0, modified: 0, deleted: 0)
}

@MainActor @Observable
final class GitStatusMonitor {
    var status: GitStatus = .empty
    private var timer: Timer?
    private var currentPath: String?

    func startMonitoring(path: String) {
        guard path != currentPath else { return }
        stopMonitoring()
        currentPath = path
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        currentPath = nil
        status = .empty
    }

    private func refresh() {
        guard let path = currentPath else { return }
        Task.detached(priority: .utility) {
            let newStatus = fetchGitStatus(at: path)
            await MainActor.run { [weak self] in
                self?.status = newStatus
            }
        }
    }
}

private func fetchGitStatus(at path: String) -> GitStatus {
    let branch = runGit(args: ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !branch.isEmpty else { return .empty }

    let porcelain = runGit(args: ["-C", path, "status", "--porcelain"])
    var added = 0
    var modified = 0
    var deleted = 0

    for line in porcelain.split(separator: "\n") {
        guard line.count >= 2 else { continue }
        let index = line[line.startIndex]
        let worktree = line[line.index(after: line.startIndex)]

        if index == "?" || worktree == "?" {
            added += 1
        } else if index == "D" || worktree == "D" {
            deleted += 1
        } else if index == "M" || worktree == "M" || index == "R" || worktree == "R" {
            modified += 1
        } else if index == "A" {
            added += 1
        }
    }

    return GitStatus(branch: branch, added: added, modified: modified, deleted: deleted)
}

private func runGit(args: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
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
