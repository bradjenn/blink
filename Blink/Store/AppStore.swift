import SwiftUI

enum ActiveView {
    case projects
    case settings
}

private enum StorageKeys {
    static let theme = "blink.theme"
    static let backgroundImage = "blink.backgroundImage"
    static let backgroundOpacity = "blink.backgroundOpacity"
    static let backgroundBlur = "blink.backgroundBlur"
    static let sidebarVisible = "blink.sidebarVisible"
}

@Observable
final class AppStore {
    // Projects
    var projects: [Project] = Project.dummy
    var activeProjectId: String?

    // Tabs
    var tabs: [AppTab] = AppTab.dummy
    var activeTabId: String?

    // Theme
    var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: StorageKeys.theme) }
    }

    // View
    var activeView: ActiveView = .projects

    // Background
    var backgroundImage: String? {
        didSet { UserDefaults.standard.set(backgroundImage, forKey: StorageKeys.backgroundImage) }
    }
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: StorageKeys.backgroundOpacity) }
    }
    var backgroundBlur: Double {
        didSet { UserDefaults.standard.set(backgroundBlur, forKey: StorageKeys.backgroundBlur) }
    }

    // Sidebar
    var sidebarVisible: Bool {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: StorageKeys.sidebarVisible) }
    }

    init() {
        let defaults = UserDefaults.standard

        self.theme = defaults.string(forKey: StorageKeys.theme) ?? "Josean"
        self.backgroundImage = defaults.string(forKey: StorageKeys.backgroundImage)
        self.sidebarVisible = defaults.object(forKey: StorageKeys.sidebarVisible) as? Bool ?? true

        // Double defaults to 0.0 if unset, so check for existence
        if defaults.object(forKey: StorageKeys.backgroundOpacity) != nil {
            self.backgroundOpacity = defaults.double(forKey: StorageKeys.backgroundOpacity)
        } else {
            self.backgroundOpacity = 0.75
        }

        if defaults.object(forKey: StorageKeys.backgroundBlur) != nil {
            self.backgroundBlur = defaults.double(forKey: StorageKeys.backgroundBlur)
        } else {
            self.backgroundBlur = 0
        }
    }

    // MARK: - View Actions

    func setActiveView(_ view: ActiveView) {
        activeView = view
    }

    // MARK: - Background Actions

    func setBackgroundImage(_ image: String?) {
        backgroundImage = image
    }

    func setBackgroundOpacity(_ opacity: Double) {
        backgroundOpacity = max(0.1, min(1.0, opacity))
    }

    func setBackgroundBlur(_ blur: Double) {
        backgroundBlur = max(0, min(32, blur))
    }

    var hasWallpaper: Bool {
        backgroundImage != nil
    }

    // MARK: - Actions

    func setActiveProject(_ id: String?) {
        activeProjectId = id
        activeView = .projects
        if let id {
            let projectTabs = projectTabs(for: id)
            activeTabId = projectTabs.first?.id
        } else {
            activeTabId = nil
        }
    }

    func setActiveTab(_ id: String) {
        activeTabId = id
    }

    func projectTabs(for projectId: String) -> [AppTab] {
        tabs.filter { $0.projectId == projectId }
    }

    func terminalCount(for projectId: String) -> Int {
        tabs.filter { $0.projectId == projectId && $0.type == "shell" }.count
    }

    func removeProject(_ id: String) {
        projects.removeAll { $0.id == id }
        tabs.removeAll { $0.projectId == id }
        if activeProjectId == id {
            activeProjectId = nil
            activeTabId = nil
        }
    }

    func closeTab(_ id: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            let remaining = projectTabs(for: tab.projectId)
            activeTabId = remaining.last?.id
        }
    }
}
