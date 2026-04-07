import Foundation

struct Workspace: Identifiable, Equatable, Hashable, Codable {
    static let scratchSpaceId = "blink-scratch-space"

    let id: String
    let name: String
    let path: String
    let color: String
    let createdAt: Date

    static func scratchSpace(homePath: String = NSHomeDirectory()) -> Workspace {
        Workspace(
            id: scratchSpaceId,
            name: "Scratch Space",
            path: homePath,
            color: "#89b4fa",
            createdAt: .distantPast
        )
    }

    var isScratchSpace: Bool {
        id == Self.scratchSpaceId
    }

    /// Home directory path prefix replacement for display.
    var displayPath: String {
        path.replacing("/Users/\(NSUserName())", with: "~")
    }
}

enum WorkspaceOnboardingMode: String, CaseIterable, Identifiable {
    case existingFolder
    case createFolder

    var id: String { rawValue }
}

enum WorkspaceStarter: String, CaseIterable, Identifiable {
    case empty
    case terminal
    case aiSession
    case browser
    case git
    case neovim
    case files

    var id: String { rawValue }
}

enum WorkspaceAIProvider: String, CaseIterable, Identifiable {
    case claude
    case codex
    case opencode

    var id: String { rawValue }
}

enum WorkspaceCreationError: LocalizedError, Equatable {
    case missingWorkspaceFolder
    case missingParentFolder
    case missingFolderName
    case invalidFolderName
    case workspaceFolderDoesNotExist
    case parentFolderDoesNotExist
    case selectedPathIsNotDirectory
    case failedToCreateFolder(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspaceFolder:
            return "Choose a workspace folder."
        case .missingParentFolder:
            return "Choose a parent folder for the new workspace."
        case .missingFolderName:
            return "Enter a folder name for the new workspace."
        case .invalidFolderName:
            return "Use a simple folder name without /, . or .."
        case .workspaceFolderDoesNotExist:
            return "The selected workspace folder could not be found."
        case .parentFolderDoesNotExist:
            return "The selected parent folder could not be found."
        case .selectedPathIsNotDirectory:
            return "The selected path is not a folder."
        case .failedToCreateFolder(let path):
            return "Blink could not create \(path)."
        }
    }
}

enum WorkspaceSetupPaneKind: String, Codable, Hashable {
    case shell
    case command
    case chat
    case browser
}

struct WorkspaceSetupPane: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let kind: WorkspaceSetupPaneKind
    var label: String
    var role: String?
    var command: String?
    var workingDirectory: String?
    var browserState: BrowserPaneState?
}

struct WorkspaceSetupColumn: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var paneIds: [String]
}

struct WorkspaceSetup: Equatable, Hashable, Codable {
    let workspaceId: String
    var updatedAt: Date
    var columns: [WorkspaceSetupColumn]
    var panes: [WorkspaceSetupPane]

    private enum CodingKeys: String, CodingKey {
        case workspaceId
        case projectId
        case updatedAt
        case columns
        case panes
    }

    init(
        workspaceId: String,
        updatedAt: Date,
        columns: [WorkspaceSetupColumn],
        panes: [WorkspaceSetupPane]
    ) {
        self.workspaceId = workspaceId
        self.updatedAt = updatedAt
        self.columns = columns
        self.panes = panes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? container.decode(String.self, forKey: .projectId)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        columns = try container.decode([WorkspaceSetupColumn].self, forKey: .columns)
        panes = try container.decode([WorkspaceSetupPane].self, forKey: .panes)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceId, forKey: .workspaceId)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(columns, forKey: .columns)
        try container.encode(panes, forKey: .panes)
    }
}
