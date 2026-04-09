import AppKit
import SwiftUI

struct WorkspaceOnboarding: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store

    let onDismiss: () -> Void

    @State private var mode: WorkspaceOnboardingMode = .existingFolder
    @State private var workspaceName = ""
    @State private var existingFolderPath = ""
    @State private var parentFolderPath = ""
    @State private var newFolderName = ""
    @State private var selectedProfileId = Profile.personalId
    @State private var starter: WorkspaceStarter = .terminal
    @State private var aiProvider: WorkspaceAIProvider = .claude
    @State private var browserURL = BrowserDefaults.homePageURLString
    @State private var errorMessage: String?
    @State private var workspaceNameHasManualOverride = false
    @State private var isSyncingWorkspaceName = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case workspaceName
        case existingFolderPath
        case parentFolderPath
        case newFolderName
        case browserURL
    }

    private enum ValidationKind {
        case error
        case warning
        case info
    }

    private struct ValidationMessage {
        let text: String
        let kind: ValidationKind
    }

    private var submitButtonTitle: String {
        if duplicateWorkspace != nil {
            return "Open Workspace"
        }

        return mode == .createFolder ? "Create Workspace" : "Add Workspace"
    }

    private var canSubmit: Bool {
        hasMinimumInput && validationMessage?.kind != .error
    }

    private var starterColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    private var selectedProfile: Profile? {
        store.profile(withId: onboardingProfileId)
    }

    private var onboardingProfileId: String {
        duplicateWorkspace?.profileId ?? selectedProfileId
    }

    private var hasMinimumInput: Bool {
        switch mode {
        case .existingFolder:
            return !existingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .createFolder:
            return !parentFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var normalizedExistingFolderPath: String? {
        let trimmedPath = existingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
    }

    private var normalizedParentFolderPath: String? {
        let trimmedPath = parentFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
    }

    private var trimmedFolderName: String {
        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedTargetPath: String? {
        switch mode {
        case .existingFolder:
            return normalizedExistingFolderPath
        case .createFolder:
            guard let parentPath = normalizedParentFolderPath,
                  !trimmedFolderName.isEmpty else {
                return nil
            }

            return URL(fileURLWithPath: parentPath, isDirectory: true)
                .appendingPathComponent(trimmedFolderName, isDirectory: true)
                .standardizedFileURL
                .path
        }
    }

    private var duplicateWorkspace: Workspace? {
        guard let resolvedTargetPath else { return nil }
        return store.workspaceForPath(resolvedTargetPath)
    }

    private var starterSelectionEnabled: Bool {
        duplicateWorkspace == nil
    }

    private var validationMessage: ValidationMessage? {
        switch mode {
        case .existingFolder:
            guard let path = normalizedExistingFolderPath else { return nil }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                return ValidationMessage(
                    text: "That folder could not be found.",
                    kind: .error
                )
            }

            guard isDirectory.boolValue else {
                return ValidationMessage(
                    text: "That path is a file, not a folder.",
                    kind: .error
                )
            }

            if let duplicateWorkspace {
                return ValidationMessage(
                    text: "Already added as \(duplicateWorkspace.name). Blink will open that workspace without changing its setup.",
                    kind: .info
                )
            }

            return nil

        case .createFolder:
            guard let parentPath = normalizedParentFolderPath else { return nil }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory) else {
                return ValidationMessage(
                    text: "Choose a parent folder that exists.",
                    kind: .error
                )
            }

            guard isDirectory.boolValue else {
                return ValidationMessage(
                    text: "The parent path must be a folder.",
                    kind: .error
                )
            }

            if !trimmedFolderName.isEmpty && !store.isValidWorkspaceFolderName(trimmedFolderName) {
                return ValidationMessage(
                    text: "Use a simple folder name without /, . or ..",
                    kind: .error
                )
            }

            guard let targetPath = resolvedTargetPath else { return nil }

            if let duplicateWorkspace {
                return ValidationMessage(
                    text: "Blink already knows this path as \(duplicateWorkspace.name). Creating the folder will reopen that workspace and keep its current setup.",
                    kind: .info
                )
            }

            if FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return ValidationMessage(
                        text: "That folder already exists. Blink will import it instead of creating a new one.",
                        kind: .warning
                    )
                }

                return ValidationMessage(
                    text: "A file already exists at that path.",
                    kind: .error
                )
            }

            return nil
        }
    }

    var body: some View {
        ZStack {
            BlinkModalBackdrop(
                onDismiss: onDismiss,
                accessibilityLabel: "Dismiss workspace onboarding"
            )

            BlinkModalPanel(width: 760, cornerRadius: 14) {
                VStack(spacing: 0) {
                    onboardingHeader
                    theme.border.frame(height: 1)
                    onboardingContent
                    theme.border.frame(height: 1)
                    onboardingFooter
                }
            }
            .padding(24)
            .onAppear {
                if parentFolderPath.isEmpty {
                    parentFolderPath = defaultParentFolderPath()
                }
                if store.profile(withId: selectedProfileId) == nil {
                    selectedProfileId = store.defaultProfile.id
                }
                requestFocus()
            }
            .onChange(of: mode) {
                errorMessage = nil
                if !workspaceNameHasManualOverride {
                    syncWorkspaceNameFromDefaults()
                }
                requestFocus()
            }
            .onChange(of: newFolderName) {
                errorMessage = nil
                guard mode == .createFolder, !workspaceNameHasManualOverride else { return }
                syncWorkspaceNameFromDefaults()
            }
            .onChange(of: existingFolderPath) {
                errorMessage = nil
                guard mode == .existingFolder, !workspaceNameHasManualOverride else { return }
                syncWorkspaceNameFromDefaults()
            }
            .onChange(of: parentFolderPath) {
                errorMessage = nil
            }
            .onChange(of: starter) {
                errorMessage = nil
            }
            .onChange(of: aiProvider) {
                errorMessage = nil
            }
            .onChange(of: browserURL) {
                errorMessage = nil
            }
            .onChange(of: workspaceName) {
                errorMessage = nil
                if isSyncingWorkspaceName {
                    isSyncingWorkspaceName = false
                    return
                }

                if workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    workspaceNameHasManualOverride = false
                } else {
                    workspaceNameHasManualOverride = true
                }
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New Workspace")
                .font(Fonts.primary(size: 18, weight: .bold))
                .foregroundStyle(theme.text)

            Text("Create a new workspace or import an existing folder, then choose how Blink should open it.")
                .font(Fonts.primary(size: 12))
                .foregroundStyle(theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var onboardingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                modeSection
                namingSection
                profileSection
                starterSection
                advancedStarterSection
                setupPreviewSection
                onboardingStatusSection
            }
            .padding(20)
        }
        .frame(maxHeight: 500)
    }

    @ViewBuilder
    private var onboardingStatusSection: some View {
        if let errorMessage {
            statusMessage(errorMessage, kind: .error)
        } else if let validationMessage {
            statusMessage(validationMessage.text, kind: validationMessage.kind)
        }
    }

    private var onboardingFooter: some View {
        HStack(spacing: 12) {
            Button("Cancel") { onDismiss() }
                .buttonStyle(BlinkActionButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(submitButtonTitle) { submit() }
                .buttonStyle(BlinkActionButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Source")

            HStack(spacing: 12) {
                modeCard(.existingFolder)
                modeCard(.createFolder)
            }

            switch mode {
            case .existingFolder:
                pathField(
                    title: "Workspace Folder",
                    text: $existingFolderPath,
                    prompt: "Choose a folder to import",
                    field: .existingFolderPath,
                    browseTitle: "Browse"
                ) {
                    if let path = store.chooseExistingWorkspaceFolder(startingAt: existingFolderPath) {
                        existingFolderPath = path
                        populateWorkspaceNameIfNeeded(from: path)
                        errorMessage = nil
                    }
                }
            case .createFolder:
                pathField(
                    title: "Parent Folder",
                    text: $parentFolderPath,
                    prompt: "Choose where the workspace folder should live",
                    field: .parentFolderPath,
                    browseTitle: "Browse"
                ) {
                    if let path = store.chooseWorkspaceParentFolder(startingAt: parentFolderPath) {
                        parentFolderPath = path
                        errorMessage = nil
                    }
                }

                fieldSection(title: "Folder Name") {
                    TextField("my-workspace", text: $newFolderName)
                        .textFieldStyle(.plain)
                        .font(Fonts.primary(size: 13))
                        .foregroundStyle(theme.text)
                        .focused($focusedField, equals: .newFolderName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var namingSection: some View {
        fieldSection(title: "Workspace Name") {
            TextField(namePlaceholder, text: $workspaceName)
                .textFieldStyle(.plain)
                .font(Fonts.primary(size: 13))
                .foregroundStyle(theme.text)
                .focused($focusedField, equals: .workspaceName)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Leave blank to use the folder name.")
                .font(Fonts.primary(size: 11))
                .foregroundStyle(theme.textDim)
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Profile")

            LazyVGrid(columns: starterColumns, spacing: 12) {
                ForEach(store.profiles) { profile in
                    profileCard(profile)
                }
            }
            .opacity(starterSelectionEnabled ? 1 : 0.55)
            .allowsHitTesting(starterSelectionEnabled)

            Text(profileSectionHelpText)
                .font(Fonts.primary(size: 11))
                .foregroundStyle(theme.textDim)
        }
    }

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Open With")

            LazyVGrid(columns: starterColumns, spacing: 12) {
                ForEach(WorkspaceStarter.allCases) { item in
                    starterCard(item)
                }
            }
            .opacity(starterSelectionEnabled ? 1 : 0.55)
            .allowsHitTesting(starterSelectionEnabled)

            if !starterSelectionEnabled {
                Text("This folder already maps to a workspace in Blink, so its current setup will be preserved.")
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
            }
        }
    }

    @ViewBuilder
    private var advancedStarterSection: some View {
        if starter == .aiSession {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("AI CLI")

                HStack(spacing: 12) {
                    ForEach(WorkspaceAIProvider.allCases) { provider in
                        aiProviderCard(provider)
                    }
                }
            }
            .opacity(starterSelectionEnabled ? 1 : 0.55)
            .allowsHitTesting(starterSelectionEnabled)
        } else if starter == .browser {
            fieldSection(title: "Home Page") {
                TextField(BrowserDefaults.homePageURLString, text: $browserURL)
                    .textFieldStyle(.plain)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(theme.text)
                    .focused($focusedField, equals: .browserURL)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Leave blank to use Blink’s default home page.")
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
            }
            .opacity(starterSelectionEnabled ? 1 : 0.55)
            .allowsHitTesting(starterSelectionEnabled)
        }
    }

    private var setupPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Setup Preview")

            VStack(alignment: .leading, spacing: 14) {
                previewRow(
                    icon: previewActionIcon,
                    title: previewActionTitle,
                    detail: previewActionDetail
                )

                previewRow(
                    icon: "folder",
                    title: "Workspace Path",
                    detail: resolvedTargetPath ?? "Choose a folder to see where this workspace will live."
                )

                previewRow(
                    icon: "person.crop.square",
                    title: "Profile",
                    detail: previewProfileDetail
                )

                previewRow(
                    icon: previewStarterIcon,
                    title: previewStarterTitle,
                    detail: previewStarterDetail
                )
            }
            .padding(16)
            .background(selectionBackground(isSelected: true))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
        }
    }

    private var fieldBackground: some ShapeStyle {
        AnyShapeStyle(theme.bg2.opacity(0.75))
    }

    private var namePlaceholder: String {
        switch mode {
        case .existingFolder:
            let path = existingFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? "blink" : (path as NSString).lastPathComponent
        case .createFolder:
            let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            return folderName.isEmpty ? "my-workspace" : folderName
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Fonts.primary(size: 11, weight: .bold))
            .foregroundStyle(theme.textDim)
            .textCase(.uppercase)
    }

    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
    }

    private func pathField(
        title: String,
        text: Binding<String>,
        prompt: String,
        field: Field,
        browseTitle: String,
        onBrowse: @escaping () -> Void
    ) -> some View {
        fieldSection(title: title) {
            HStack(spacing: 10) {
                TextField(prompt, text: text)
                    .textFieldStyle(.plain)
                    .font(Fonts.primary(size: 13))
                    .foregroundStyle(theme.text)
                    .focused($focusedField, equals: field)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(browseTitle, action: onBrowse)
                    .buttonStyle(BlinkActionButtonStyle(kind: .secondaryCompact))
            }
        }
    }

    private func modeCard(_ candidate: WorkspaceOnboardingMode) -> some View {
        let isSelected = candidate == mode

        return Button {
            mode = candidate
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.title)
                    .font(Fonts.primary(size: 13, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(candidate.subtitle)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(selectionBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func starterCard(_ candidate: WorkspaceStarter) -> some View {
        let isSelected = candidate == starter

        return Button {
            starter = candidate
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: candidate.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.accent)

                Text(candidate.title)
                    .font(Fonts.primary(size: 13, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(candidate.subtitle)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(selectionBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func aiProviderCard(_ candidate: WorkspaceAIProvider) -> some View {
        let isSelected = candidate == aiProvider

        return Button {
            aiProvider = candidate
        } label: {
            HStack {
                Text(candidate.title)
                    .font(Fonts.primary(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(selectionBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func profileCard(_ profile: Profile) -> some View {
        let isSelected = profile.id == onboardingProfileId

        return Button {
            selectedProfileId = profile.id
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: profile.color))
                    .frame(width: 9, height: 9)

                Text(profile.name)
                    .font(Fonts.primary(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if profile.isBuiltIn {
                    Text("Default")
                        .font(Fonts.primary(size: 10, weight: .medium))
                        .foregroundStyle(theme.textDim)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(selectionBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.75) : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func selectionBackground(isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.12))
        }
        return AnyShapeStyle(theme.bg2.opacity(0.45))
    }

    private var previewActionIcon: String {
        if duplicateWorkspace != nil {
            return "arrow.turn.down.right"
        }

        switch mode {
        case .existingFolder:
            return "square.and.arrow.down"
        case .createFolder:
            return "folder.badge.plus"
        }
    }

    private var previewActionTitle: String {
        if duplicateWorkspace != nil {
            return "Open Existing Workspace"
        }

        switch mode {
        case .existingFolder:
            return "Import Folder"
        case .createFolder:
            return "Create Workspace Folder"
        }
    }

    private var previewActionDetail: String {
        if let duplicateWorkspace {
            return "\(duplicateWorkspace.name) will open and keep its current tabs and saved layout."
        }

        switch mode {
        case .existingFolder:
            return "Blink will add this folder as a workspace and open it."
        case .createFolder:
            return "Blink will create the folder if needed, then open it as a workspace."
        }
    }

    private var previewStarterIcon: String {
        starterSelectionEnabled ? starter.systemImage : "square.stack"
    }

    private var previewStarterTitle: String {
        if duplicateWorkspace != nil {
            return "Current Setup"
        }

        return starter.title
    }

    private var previewStarterDetail: String {
        if let duplicateWorkspace {
            return "Starter choices are disabled because \(duplicateWorkspace.name) already exists in Blink."
        }

        switch starter {
        case .empty:
            return "Opens to the workspace landing page with no initial panes."
        case .terminal:
            return "Starts with a shell pane in the workspace directory."
        case .aiSession:
            return "Starts with \(aiProvider.title) in a tracked command pane."
        case .browser:
            let target = browserPreviewURL ?? BrowserDefaults.homePageURLString
            return "Starts with Workspace Browser pointed at \(target)."
        case .git:
            return "Starts with lazygit in the workspace directory."
        case .neovim:
            return "Starts with Neovim ready in the workspace directory."
        case .files:
            return "Starts with Yazi browsing the workspace directory."
        }
    }

    private var profileSectionHelpText: String {
        if let duplicateWorkspace {
            let profileName = store.profileName(for: duplicateWorkspace.profileId)
            return "\(duplicateWorkspace.name) already uses the \(profileName) profile."
        }

        return "Profiles share browser sessions and logins across attached workspaces."
    }

    private var previewProfileDetail: String {
        let profileName = selectedProfile?.name ?? store.defaultProfile.name
        if let duplicateWorkspace {
            return "\(duplicateWorkspace.name) will keep using the \(profileName) profile."
        }
        return "This workspace will use the \(profileName) profile for shared browser sessions."
    }

    private var browserPreviewURL: String? {
        let trimmedURL = browserURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }
        return BrowserURLResolver.resolve(trimmedURL)?.absoluteString ?? trimmedURL
    }

    private func previewRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Fonts.primary(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)

                Text(detail)
                    .font(Fonts.primary(size: 11))
                    .foregroundStyle(theme.textDim)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    private func statusMessage(_ text: String, kind: ValidationKind) -> some View {
        Text(text)
            .font(Fonts.primary(size: 12))
            .foregroundStyle(statusForeground(kind))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusBackground(kind))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusForeground(_ kind: ValidationKind) -> Color {
        switch kind {
        case .error:
            return theme.accent2
        case .warning:
            return theme.yellow
        case .info:
            return theme.text
        }
    }

    private func statusBackground(_ kind: ValidationKind) -> some ShapeStyle {
        switch kind {
        case .error:
            return AnyShapeStyle(theme.accent2.opacity(0.08))
        case .warning:
            return AnyShapeStyle(theme.yellow.opacity(0.1))
        case .info:
            return AnyShapeStyle(theme.accent.opacity(0.08))
        }
    }

    private func populateWorkspaceNameIfNeeded(from path: String) {
        guard !workspaceNameHasManualOverride else { return }
        syncWorkspaceName((path as NSString).lastPathComponent)
    }

    private func syncWorkspaceNameFromDefaults() {
        syncWorkspaceName(namePlaceholder)
    }

    private func syncWorkspaceName(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard workspaceName != trimmedValue else { return }
        isSyncingWorkspaceName = true
        workspaceName = trimmedValue
    }

    private func requestFocus() {
        DispatchQueue.main.async {
            switch mode {
            case .existingFolder:
                focusedField = existingFolderPath.isEmpty ? .existingFolderPath : .workspaceName
            case .createFolder:
                focusedField = newFolderName.isEmpty ? .newFolderName : .workspaceName
            }
        }
    }

    private func defaultParentFolderPath() -> String {
        let codePath = (NSHomeDirectory() as NSString).appendingPathComponent("Code")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: codePath, isDirectory: &isDirectory), isDirectory.boolValue {
            return codePath
        }
        return NSHomeDirectory()
    }

    private func submit() {
        errorMessage = nil

        do {
            _ = try store.completeWorkspaceOnboarding(
                mode: mode,
                name: workspaceName,
                existingFolderPath: existingFolderPath,
                parentFolderPath: parentFolderPath,
                newFolderName: newFolderName,
                profileId: onboardingProfileId,
                starter: starter,
                aiProvider: aiProvider,
                browserURL: browserURL
            )
            onDismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private extension WorkspaceOnboardingMode {
    var title: String {
        switch self {
        case .existingFolder:
            return "Existing Folder"
        case .createFolder:
            return "Create Folder"
        }
    }

    var subtitle: String {
        switch self {
        case .existingFolder:
            return "Import a repo or directory that already exists."
        case .createFolder:
            return "Create a new workspace folder before opening it."
        }
    }
}

private extension WorkspaceStarter {
    var title: String {
        switch self {
        case .empty:
            return "Start Empty"
        case .terminal:
            return "Terminal"
        case .aiSession:
            return "AI Session"
        case .browser:
            return "Browser"
        case .git:
            return "Git"
        case .neovim:
            return "Neovim"
        case .files:
            return "Files"
        }
    }

    var subtitle: String {
        switch self {
        case .empty:
            return "Open to the landing page."
        case .terminal:
            return "Start with a shell pane."
        case .aiSession:
            return "Launch a CLI coding agent."
        case .browser:
            return "Open an isolated browser pane."
        case .git:
            return "Open lazygit."
        case .neovim:
            return "Open Neovim."
        case .files:
            return "Browse files with Yazi."
        }
    }

    var systemImage: String {
        switch self {
        case .empty:
            return "square.dashed"
        case .terminal:
            return "terminal"
        case .aiSession:
            return "sparkles.rectangle.stack"
        case .browser:
            return "globe"
        case .git:
            return "point.3.connected.trianglepath.dotted"
        case .neovim:
            return "square.and.pencil"
        case .files:
            return "folder"
        }
    }
}

private extension WorkspaceAIProvider {
    var title: String {
        switch self {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }
}
