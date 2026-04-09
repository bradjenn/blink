import AppKit
import SwiftUI

struct SettingsPage: View {
    private enum Layout {
        static let sidebarLeadingPadding: CGFloat = 52
    }

    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let ghosttyApp: GhosttyApp

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case terminal = "Terminal"
        case profiles = "Profiles"
        case keyboardShortcuts = "Keyboard Shortcuts"
    }

    @State private var selectedTab: SettingsTab = .appearance
    @State private var isCloseHovered = false
    @State private var closePressed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Nav sidebar — sits to the left of the content max-width
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            SettingsTabButton(
                                label: tab.rawValue,
                                badgeText: nil,
                                isActive: selectedTab == tab,
                                action: { selectedTab = tab }
                            )
                        }
                    }
                    .frame(width: 180)
                    .padding(.top, 20)
                    .padding(.leading, Layout.sidebarLeadingPadding)
                    .padding(.trailing, 12)

                    // Content area — fixed max width, scrollbar hugs right edge
                    switch selectedTab {
                    case .appearance:
                        AppearanceSettings(ghosttyApp: ghosttyApp)
                    case .terminal:
                        TerminalSettings(ghosttyApp: ghosttyApp)
                    case .profiles:
                        ProfilesSettings()
                    case .keyboardShortcuts:
                        KeyboardShortcutsSettings()
                    }
                }
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Close button — top left
            Button(action: {
                withAnimation(.easeOut(duration: 0.12)) { closePressed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    store.toggleSettings()
                    closePressed = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCloseHovered ? theme.text : theme.textMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isCloseHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isCloseHovered ? theme.textMuted.opacity(0.4) : theme.border,
                                lineWidth: 1
                            )
                    )
                    .scaleEffect(closePressed ? 0.85 : 1.0)
                    .opacity(closePressed ? 0.6 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .pointerCursor()
            .animation(.easeOut(duration: 0.15), value: isCloseHovered)
            .padding(.leading, 10)
            .padding(.top, 10)
        }
        .font(Fonts.primary(size: 13, family: store.uiFontFamily))
    }
}

private struct ProfilesSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    @State private var newProfileName = ""
    @State private var editingProfileId: String?
    @State private var renameDraft = ""
    @State private var pendingRemovalProfile: Profile?

    private var activeWorkspace: Workspace? {
        guard let activeWorkspaceId = store.activeWorkspaceId else { return nil }
        return store.workspaces.first(where: { $0.id == activeWorkspaceId })
    }

    private var profilesWithSharedSessionsCount: Int {
        store.profiles.filter { attachedWorkspaces(for: $0).count > 1 }.count
    }

    private var totalProfileAssignmentsCount: Int {
        store.workspaces.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            profilesHeader
            profileSummaryRow
            profileAssignmentCard
            createProfileCard
            profileDirectoryCard
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            pendingRemovalProfile.map { "Remove \($0.name)?" } ?? "Remove Profile?",
            isPresented: Binding(
                get: { pendingRemovalProfile != nil },
                set: { if !$0 { pendingRemovalProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = pendingRemovalProfile {
                Button("Remove Profile", role: .destructive) {
                    _ = store.removeProfile(profile.id)
                    pendingRemovalProfile = nil
                    if editingProfileId == profile.id {
                        editingProfileId = nil
                        renameDraft = ""
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingRemovalProfile = nil
            }
        } message: {
            if let profile = pendingRemovalProfile {
                Text(removalMessage(for: profile))
            }
        }
    }

    private var profilesHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles")
                .font(Fonts.primary(size: 26, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.text)

            Text("Profiles control which workspaces share browser sessions, cookies, and sign-ins.")
                .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
        }
    }

    private var profileSummaryRow: some View {
        HStack(spacing: 12) {
            profileMetricCard(
                title: "Profiles",
                value: "\(store.profiles.count)",
                subtitle: "\(store.profiles.filter(\.isBuiltIn).count) built in"
            )

            profileMetricCard(
                title: "Attached Workspaces",
                value: "\(totalProfileAssignmentsCount)",
                subtitle: totalProfileAssignmentsCount == 1 ? "1 workspace linked" : "\(totalProfileAssignmentsCount) workspaces linked"
            )

            profileMetricCard(
                title: "Shared Sessions",
                value: "\(profilesWithSharedSessionsCount)",
                subtitle: profilesWithSharedSessionsCount == 1 ? "1 profile shared" : "\(profilesWithSharedSessionsCount) profiles shared"
            )
        }
    }

    private func profileMetricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Fonts.primary(size: 11, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
                .textCase(.uppercase)

            Text(value)
                .font(Fonts.primary(size: 22, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.text)

            Text(subtitle)
                .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var profileAssignmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current Workspace")
                .font(Fonts.primary(size: 12, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)

            if let activeWorkspace {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        WorkspaceFavicon(
                            workspaceName: activeWorkspace.name,
                            workspacePath: activeWorkspace.path,
                            size: 26
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeWorkspace.name)
                                .font(Fonts.primary(size: 15, weight: .bold, family: store.uiFontFamily))
                                .foregroundStyle(theme.text)

                            Text(activeWorkspace.displayPath)
                                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                                .foregroundStyle(theme.textDim)
                        }

                        Spacer(minLength: 0)

                        if let profile = store.profile(withId: activeWorkspace.profileId) {
                            profilePill(profile, label: "Current Profile")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Move This Workspace")
                            .font(Fonts.primary(size: 11, weight: .bold, family: store.uiFontFamily))
                            .foregroundStyle(theme.textDim)
                            .textCase(.uppercase)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(store.profiles) { profile in
                                profileSelectionRow(
                                    profile: profile,
                                    isSelected: activeWorkspace.profileId == profile.id,
                                    workspaceCount: store.workspaces.filter { $0.profileId == profile.id }.count
                                ) {
                                    assign(activeWorkspace, to: profile)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Open a workspace to decide which browser session it should share.")
                    .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var createProfileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Profile")
                .font(Fonts.primary(size: 12, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)

            HStack(spacing: 12) {
                TextField("Client A", text: $newProfileName)
                    .textFieldStyle(.plain)
                    .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.bg2.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        createProfile()
                    }

                Button("Add Profile") {
                    createProfile()
                }
                .buttonStyle(BlinkActionButtonStyle(kind: .primary))
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Use a separate profile for a client, company account, or any browsing context that should not share cookies.")
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
        }
        .padding(18)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var profileDirectoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile Library")
                .font(Fonts.primary(size: 12, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)

            ForEach(store.profiles) { profile in
                profileCard(profile)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func profileSelectionRow(
        profile: Profile,
        isSelected: Bool,
        workspaceCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: profile.color))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(Fonts.primary(size: 13, weight: .bold, family: store.uiFontFamily))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(workspaceCount == 0 ? "No attached workspaces" : "\(workspaceCount) attached workspace\(workspaceCount == 1 ? "" : "s")")
                        .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                        .foregroundStyle(theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accent.opacity(0.12) : theme.bg2.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func profileCard(_ profile: Profile) -> some View {
        let workspaces = attachedWorkspaces(for: profile)
        let isEditing = editingProfileId == profile.id
        let isCurrentProfile = activeWorkspace?.profileId == profile.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color(hex: profile.color))
                            .frame(width: 12, height: 12)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 8) {
                            if isEditing {
                                TextField("Profile Name", text: $renameDraft)
                                    .textFieldStyle(.plain)
                                    .font(Fonts.primary(size: 15, weight: .bold, family: store.uiFontFamily))
                                    .foregroundStyle(theme.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(theme.bg2.opacity(0.75))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .onSubmit {
                                        saveRename(for: profile)
                                    }
                            } else {
                                Text(profile.name)
                                    .font(Fonts.primary(size: 15, weight: .bold, family: store.uiFontFamily))
                                    .foregroundStyle(theme.text)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let activeWorkspace, activeWorkspace.profileId != profile.id {
                        Button("Move Current Here") {
                            assign(activeWorkspace, to: profile)
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))
                    }

                    if profile.isBuiltIn {
                        EmptyView()
                    } else if isEditing {
                        Button("Cancel") {
                            cancelRename()
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))

                        Button("Save") {
                            saveRename(for: profile)
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .primary))
                        .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Rename") {
                            beginRenaming(profile)
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))

                        Button("Remove") {
                            pendingRemovalProfile = profile
                        }
                        .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))
                    }
                }
            }

            HStack(spacing: 8) {
                if profile.isBuiltIn {
                    profileMetaTag("Default")
                }

                if isCurrentProfile {
                    profileMetaTag("Current Workspace")
                }

                if workspaces.count > 1 {
                    profileMetaTag("Shared Session")
                } else if workspaces.count == 1 {
                    profileMetaTag("Isolated Session")
                } else {
                    profileMetaTag("Empty")
                }
            }

            Text(profileDescription(for: profile, workspaces: workspaces))
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)

            VStack(alignment: .leading, spacing: 10) {
                Text("Attached Workspaces")
                    .font(Fonts.primary(size: 11, weight: .bold, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
                    .textCase(.uppercase)

                if workspaces.isEmpty {
                    Text("No workspaces use this profile yet.")
                        .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                        .foregroundStyle(theme.textDim)
                } else {
                    ProfileWorkspaceReorderList(
                        workspaces: workspaces,
                        activeWorkspaceId: activeWorkspace?.id,
                        theme: theme,
                        uiFontFamily: store.uiFontFamily
                    ) { workspaceId, insertionIndex in
                        store.reorderWorkspace(workspaceId, inProfile: profile.id, to: insertionIndex)
                    }
                    .frame(height: ProfileWorkspaceReorderList.height(for: workspaces.count))
                }
            }
        }
        .padding(16)
        .background(theme.bg2.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCurrentProfile ? theme.accent.opacity(0.55) : theme.border, lineWidth: 1)
        )
    }

    private func profilePill(_ profile: Profile, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(Fonts.primary(size: 10, weight: .bold, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: profile.color))
                    .frame(width: 8, height: 8)

                Text(profile.name)
                    .font(Fonts.primary(size: 12, weight: .bold, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.bg2.opacity(0.72))
            .clipShape(Capsule(style: .continuous))
        }
    }

    private func profileMetaTag(_ label: String) -> some View {
        Text(label)
            .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
            .foregroundStyle(theme.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule(style: .continuous))
    }

    private func attachedWorkspaces(for profile: Profile) -> [Workspace] {
        store.workspaces.filter { $0.profileId == profile.id }
    }

    private func assign(_ workspace: Workspace, to profile: Profile) {
        _ = store.setWorkspaceProfile(workspace.id, profileId: profile.id)
    }

    private func createProfile() {
        guard let profile = store.addProfile(name: newProfileName) else { return }
        if let activeWorkspace {
            _ = store.setWorkspaceProfile(activeWorkspace.id, profileId: profile.id)
        }
        newProfileName = ""
    }

    private func beginRenaming(_ profile: Profile) {
        editingProfileId = profile.id
        renameDraft = profile.name
    }

    private func cancelRename() {
        editingProfileId = nil
        renameDraft = ""
    }

    private func saveRename(for profile: Profile) {
        guard store.renameProfile(profile.id, to: renameDraft) else { return }
        editingProfileId = nil
        renameDraft = ""
    }

    private func profileDescription(for profile: Profile, workspaces: [Workspace]) -> String {
        if profile.isBuiltIn {
            return workspaces.isEmpty
                ? "The fallback profile for new or reassigned workspaces."
                : "The fallback profile shared by workspaces that should stay in your default browser session."
        }

        if workspaces.isEmpty {
            return "Ready for a separate client or account. Nothing is attached yet."
        }

        if workspaces.count == 1 {
            return "This profile is isolated to one workspace."
        }

        return "These \(workspaces.count) workspaces share one Chromium session."
    }

    private func removalMessage(for profile: Profile) -> String {
        let workspaceCount = attachedWorkspaces(for: profile).count
        let workspaceSummary = workspaceCount == 1 ? "1 attached workspace" : "\(workspaceCount) attached workspaces"
        return "\(workspaceSummary) will be moved to Personal, and Blink will delete this profile’s Chromium storage."
    }
}

private struct ProfileWorkspaceReorderList: NSViewRepresentable {
    private static let pasteboardType = NSPasteboard.PasteboardType("dev.blink.profile-workspace")
    private static let tableColumnIdentifier = NSUserInterfaceItemIdentifier("ProfileWorkspaceColumn")
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ProfileWorkspaceCell")
    private static let rowHeight: CGFloat = 60

    let workspaces: [Workspace]
    let activeWorkspaceId: String?
    let theme: Theme
    let uiFontFamily: String
    let onMove: (String, Int) -> Bool

    static func height(for rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + 20
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ProfileWorkspaceListContainerView {
        let tableView = ProfileWorkspaceTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = .zero
        tableView.rowHeight = Self.rowHeight
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.style = .plain
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.registerForDraggedTypes([Self.pasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let column = NSTableColumn(identifier: Self.tableColumnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let containerView = ProfileWorkspaceListContainerView(tableView: tableView)
        context.coordinator.tableView = tableView
        return containerView
    }

    func updateNSView(_ nsView: ProfileWorkspaceListContainerView, context: Context) {
        context.coordinator.parent = self

        guard let tableView = context.coordinator.tableView else { return }
        if let column = tableView.tableColumns.first {
            column.width = max(nsView.bounds.width, 0)
        }

        context.coordinator.reloadIfNeeded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ProfileWorkspaceReorderList
        weak var tableView: NSTableView?

        private var workspaceIDs: [String]
        private var draggedWorkspaceID: String?
        private var pendingDroppedWorkspaceID: String?
        private var isAnimatingMove = false

        init(parent: ProfileWorkspaceReorderList) {
            self.parent = parent
            self.workspaceIDs = parent.workspaces.map(\.id)
        }

        func reloadIfNeeded() {
            let updatedWorkspaceIDs = parent.workspaces.map(\.id)
            guard updatedWorkspaceIDs != workspaceIDs else {
                if !isAnimatingMove {
                    refreshVisibleRows()
                }
                return
            }

            guard !isAnimatingMove else { return }

            if let tableView,
               let move = singleMove(from: workspaceIDs, to: updatedWorkspaceIDs) {
                animateMove(move, updatedWorkspaceIDs: updatedWorkspaceIDs, in: tableView)
                return
            }

            workspaceIDs = updatedWorkspaceIDs
            tableView?.reloadData()
            finishDropIfNeeded()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            workspaceIDs.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            ProfileWorkspaceReorderList.rowHeight
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            draggedWorkspaceID = rowIndexes.first.flatMap { row in
                parent.workspaces.indices.contains(row) ? parent.workspaces[row].id : nil
            }
            session.animatesToStartingPositionsOnCancelOrFail = true
            session.draggingFormation = .none
            tableView.draggingDestinationFeedbackStyle = .gap
            refreshVisibleRows()
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            guard pendingDroppedWorkspaceID == nil else { return }
            draggedWorkspaceID = nil
            refreshVisibleRows()
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard parent.workspaces.indices.contains(row) else { return nil }

            let item = NSPasteboardItem()
            item.setString(parent.workspaces[row].id, forType: ProfileWorkspaceReorderList.pasteboardType)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard draggedWorkspaceID(from: info) != nil else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard let workspaceID = draggedWorkspaceID(from: info) else { return false }
            let didMove = parent.onMove(workspaceID, row)
            pendingDroppedWorkspaceID = didMove ? workspaceID : nil
            if !didMove {
                draggedWorkspaceID = nil
            }
            return didMove
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let workspace = displayedWorkspace(at: row) else { return nil }
            let cellView = (tableView.makeView(
                withIdentifier: ProfileWorkspaceReorderList.cellIdentifier,
                owner: nil
            ) as? ProfileWorkspaceCellView) ?? ProfileWorkspaceCellView()
            cellView.identifier = ProfileWorkspaceReorderList.cellIdentifier
            cellView.configure(
                workspace: workspace,
                isActive: workspace.id == parent.activeWorkspaceId,
                isDragged: workspace.id == draggedWorkspaceID,
                theme: parent.theme,
                uiFontFamily: parent.uiFontFamily
            )
            return cellView
        }

        private func refreshVisibleRows() {
            guard let tableView else { return }

            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.length > 0 else { return }

            for row in visibleRows.location ..< (visibleRows.location + visibleRows.length) {
                guard let workspace = displayedWorkspace(at: row),
                      let cellView = tableView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: true
                      ) as? ProfileWorkspaceCellView else {
                    continue
                }

                cellView.configure(
                    workspace: workspace,
                    isActive: workspace.id == parent.activeWorkspaceId,
                    isDragged: workspace.id == draggedWorkspaceID,
                    theme: parent.theme,
                    uiFontFamily: parent.uiFontFamily
                )
            }
        }

        private func animateMove(_ move: RowMove, updatedWorkspaceIDs: [String], in tableView: NSTableView) {
            isAnimatingMove = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.allowsImplicitAnimation = true
                tableView.beginUpdates()
                tableView.moveRow(at: move.from, to: move.to)
                tableView.endUpdates()
            } completionHandler: { [weak self] in
                self?.workspaceIDs = updatedWorkspaceIDs
                self?.isAnimatingMove = false
                self?.finishDropIfNeeded()
                DispatchQueue.main.async { [weak self, weak tableView] in
                    guard let self, let tableView else { return }
                    tableView.reloadData()
                    self.refreshVisibleRows()
                }
            }
        }

        private func finishDropIfNeeded() {
            guard let pendingDroppedWorkspaceID else { return }
            if draggedWorkspaceID == pendingDroppedWorkspaceID {
                draggedWorkspaceID = nil
            }
            self.pendingDroppedWorkspaceID = nil
        }

        private func affectedRows(for move: RowMove) -> IndexSet {
            let lowerBound = min(move.from, move.to)
            let upperBound = max(move.from, move.to)
            guard lowerBound <= upperBound else { return [] }
            return IndexSet(integersIn: lowerBound ... upperBound)
        }

        private func singleMove(from old: [String], to new: [String]) -> RowMove? {
            guard old.count == new.count, Set(old) == Set(new) else { return nil }

            for candidate in old {
                guard let oldIndex = old.firstIndex(of: candidate),
                      let newIndex = new.firstIndex(of: candidate),
                      oldIndex != newIndex else {
                    continue
                }

                var oldRemainder = old
                oldRemainder.remove(at: oldIndex)

                var newRemainder = new
                newRemainder.remove(at: newIndex)

                if oldRemainder == newRemainder {
                    return RowMove(from: oldIndex, to: newIndex)
                }
            }

            return nil
        }

        private func draggedWorkspaceID(from draggingInfo: NSDraggingInfo) -> String? {
            let pasteboard = draggingInfo.draggingPasteboard
            let workspaceID = pasteboard.string(forType: ProfileWorkspaceReorderList.pasteboardType)
            guard let workspaceID,
                  parent.workspaces.contains(where: { $0.id == workspaceID }) else {
                return nil
            }
            return workspaceID
        }

        private func displayedWorkspace(at row: Int) -> Workspace? {
            guard workspaceIDs.indices.contains(row) else { return nil }
            let workspaceID = workspaceIDs[row]
            return parent.workspaces.first(where: { $0.id == workspaceID })
        }
    }

    private struct RowMove {
        let from: Int
        let to: Int
    }
}

private final class ProfileWorkspaceListContainerView: NSView {
    let tableView: NSTableView

    init(tableView: NSTableView) {
        self.tableView = tableView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear

        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ProfileWorkspaceCellView: NSTableCellView {
    private static let dragPreviewInset: CGFloat = 12
    private static let verticalInset: CGFloat = 4

    private let cardView = ProfileWorkspaceCardView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        workspace: Workspace,
        isActive: Bool,
        isDragged: Bool,
        theme: Theme,
        uiFontFamily: String
    ) {
        cardView.configure(
            workspace: workspace,
            isActive: isActive,
            theme: theme,
            uiFontFamily: uiFontFamily
        )
        alphaValue = isDragged ? 0.38 : 1.0
        layer?.setAffineTransform(isDragged ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity)
    }

    override var draggingImageComponents: [NSDraggingImageComponent] {
        let component = NSDraggingImageComponent(key: .icon)
        let previewImage = dragPreviewImage()
        let inset = Self.dragPreviewInset
        component.frame = NSRect(
            x: -inset,
            y: -inset,
            width: previewImage.size.width,
            height: previewImage.size.height
        )
        component.contents = previewImage
        return [component]
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.actions = [
            "transform": NSNull(),
            "opacity": NSNull()
        ]

        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset)
        ])
    }

    private func dragPreviewImage() -> NSImage {
        let sourceBounds = bounds.integral
        guard sourceBounds.width > 0,
              sourceBounds.height > 0,
              let bitmapRep = bitmapImageRepForCachingDisplay(in: sourceBounds) else {
            return NSImage(size: sourceBounds.size)
        }

        cacheDisplay(in: sourceBounds, to: bitmapRep)

        let sourceImage = NSImage(size: sourceBounds.size)
        sourceImage.addRepresentation(bitmapRep)

        let scale: CGFloat = 1.025
        let inset = Self.dragPreviewInset
        let previewSize = NSSize(
            width: (sourceBounds.width * scale) + (inset * 2),
            height: (sourceBounds.height * scale) + (inset * 2)
        )

        let previewImage = NSImage(size: previewSize)
        previewImage.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setShadow(
                offset: CGSize(width: 0, height: -10),
                blur: 24,
                color: NSColor.black.withAlphaComponent(0.28).cgColor
            )
        }

        sourceImage.draw(
            in: NSRect(
                x: inset,
                y: inset,
                width: sourceBounds.width * scale,
                height: sourceBounds.height * scale
            ),
            from: sourceBounds,
            operation: .sourceOver,
            fraction: 0.98
        )
        previewImage.unlockFocus()
        return previewImage
    }
}

private final class ProfileWorkspaceTableView: NSTableView {
    override func autoscroll(with event: NSEvent) -> Bool {
        false
    }

    override func scrollWheel(with event: NSEvent) {
        // Attached workspace reordering is a fixed-height surface, not a scroll region.
    }
}

private final class ProfileWorkspaceCardView: NSView {
    private let faviconView = ProfileWorkspaceFaviconView(size: 20)
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let activeBadge = ProfileWorkspaceBadgeView()
    private let gripView = NSImageView()
    private let textStack = NSStackView()
    private let titleRow = NSStackView()
    private let rootStack = NSStackView()
    private let spacerView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        workspace: Workspace,
        isActive: Bool,
        theme: Theme,
        uiFontFamily: String
    ) {
        layer?.backgroundColor = NSColor(Color.white.opacity(0.03)).cgColor
        layer?.borderColor = NSColor(theme.border.opacity(0.85)).cgColor

        faviconView.configure(
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            theme: theme
        )

        nameLabel.stringValue = workspace.name
        nameLabel.textColor = NSColor(theme.text)
        nameLabel.font = ProfileWorkspaceRowMetrics.font(size: 13, weight: .bold, family: uiFontFamily)

        pathLabel.stringValue = workspace.displayPath
        pathLabel.textColor = NSColor(theme.textDim)
        pathLabel.font = ProfileWorkspaceRowMetrics.font(size: 11, weight: .regular, family: uiFontFamily)

        activeBadge.isHidden = !isActive
        if isActive {
            activeBadge.configure(
                title: "Open",
                textColor: NSColor(theme.textDim),
                backgroundColor: NSColor(Color.white.opacity(0.05)),
                font: ProfileWorkspaceRowMetrics.font(size: 10, weight: .medium, family: uiFontFamily)
            )
        }

        gripView.contentTintColor = NSColor(theme.textDim)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        layer?.actions = [
            "backgroundColor": NSNull(),
            "borderColor": NSNull()
        ]

        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.lineBreakMode = .byTruncatingMiddle

        gripView.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: nil
        )
        gripView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        gripView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gripView.widthAnchor.constraint(equalToConstant: 12),
            gripView.heightAnchor.constraint(equalToConstant: 12)
        ])

        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.addArrangedSubview(nameLabel)
        titleRow.addArrangedSubview(activeBadge)
        titleRow.setCustomSpacing(0, after: activeBadge)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(titleRow)
        textStack.addArrangedSubview(pathLabel)

        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(faviconView)
        rootStack.addArrangedSubview(textStack)
        rootStack.addArrangedSubview(spacerView)
        rootStack.addArrangedSubview(gripView)

        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private final class ProfileWorkspaceFaviconView: NSView {
    private let size: CGFloat
    private let imageView = NSImageView()
    private let initialLabel = NSTextField(labelWithString: "")
    private let fallbackImageView = NSImageView()

    init(size: CGFloat) {
        self.size = size
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(workspaceName: String, workspacePath: String, theme: Theme) {
        layer?.backgroundColor = NSColor(theme.border).cgColor

        if let image = WorkspaceFavicon.faviconImage(workspacePath: workspacePath, size: size) {
            imageView.image = image
            imageView.isHidden = false
            initialLabel.isHidden = true
            fallbackImageView.isHidden = true
            return
        }

        let initial = String(workspaceName.prefix(1)).uppercased()
        if initial.isEmpty {
            fallbackImageView.contentTintColor = NSColor(theme.textMuted)
            fallbackImageView.isHidden = false
            imageView.isHidden = true
            initialLabel.isHidden = true
        } else {
            initialLabel.stringValue = initial
            initialLabel.textColor = NSColor(theme.text)
            initialLabel.font = ProfileWorkspaceRowMetrics.font(size: size * 0.42, weight: .bold, family: Fonts.defaultFamily)
            initialLabel.isHidden = false
            imageView.isHidden = true
            fallbackImageView.isHidden = true
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = size * 0.22
        layer?.masksToBounds = true

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size)
        ])

        [imageView, initialLabel, fallbackImageView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
            NSLayoutConstraint.activate([
                $0.leadingAnchor.constraint(equalTo: leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: trailingAnchor),
                $0.topAnchor.constraint(equalTo: topAnchor),
                $0.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        imageView.imageScaling = .scaleAxesIndependently

        initialLabel.alignment = .center
        initialLabel.isBordered = false
        initialLabel.backgroundColor = .clear
        initialLabel.isEditable = false

        fallbackImageView.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: nil
        )
        fallbackImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .medium)
        fallbackImageView.imageScaling = .scaleProportionallyDown
        fallbackImageView.isHidden = true
    }
}

private final class ProfileWorkspaceBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, textColor: NSColor, backgroundColor: NSColor, font: NSFont) {
        label.stringValue = title
        label.textColor = textColor
        label.font = font
        layer?.backgroundColor = backgroundColor.cgColor
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}

private enum ProfileWorkspaceRowMetrics {
    static func font(size: CGFloat, weight: NSFont.Weight, family: String) -> NSFont {
        if family == Fonts.defaultFamily {
            let name = weight == .bold || weight == .semibold ? "MesloLGSNFM-Bold" : "MesloLGSNFM-Regular"
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        if let font = NSFont(name: family, size: size) {
            if weight == .regular {
                return font
            }

            let descriptor = font.fontDescriptor.addingAttributes([
                .traits: [
                    NSFontDescriptor.TraitKey.weight: weight
                ]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? font
        }

        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

private struct SettingsTabButton: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let label: String
    let badgeText: String?
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(Fonts.primary(size: 14, family: store.uiFontFamily))
                    .foregroundStyle(isActive ? theme.text : isHovered ? theme.text : theme.textMuted)

                if let badgeText {
                    Text(badgeText)
                        .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.accent.opacity(0.14))
                        )
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.06) : isHovered ? Color.white.opacity(0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
