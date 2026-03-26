import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectChatView: View {
    @Environment(\.theme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(ChatStore.self) private var chatStore
    let tabId: String
    let threadId: String
    let project: Project

    @State private var draft = ""
    @State private var editorHeight: CGFloat = 20
    @State private var keyMonitor: Any?
    @State private var composerFocused = false
    @State private var showModelMenu = false
    @State private var showCodexModelMenu = false
    @State private var showClaudeModelMenu = false
    @State private var showModeMenu = false
    @State private var showPlanningSettingsMenu = false
    @State private var showEffortMenu = false
    @State private var showPermissionMenu = false
    @State private var showAttachmentImporter = false
    @State private var launchingImplementationProvider: ChatProvider?
    @State private var planningPanelError: String?
    @State private var expandedWorkLogMessageIds: Set<String> = []
    @State private var hoveredHistoryThreadId: String?
    @State private var pendingDeletionThread: ChatThread?
    @State private var pendingAttachments: [ChatAttachment] = []

    private let maxVisibleWorkLogItems = 3

    private enum MessageDisplayItem: Identifiable {
        case single(ChatMessage)
        case comparisonPair(id: String, left: ChatMessage, right: ChatMessage)

        var id: String {
            switch self {
            case .single(let message):
                message.id
            case .comparisonPair(let id, _, _):
                "comparison-\(id)"
            }
        }
    }

    private var thread: ChatThread? {
        chatStore.thread(threadId)
    }

    private var messages: [ChatMessage] {
        chatStore.messages(for: threadId)
    }

    private var displayItems: [MessageDisplayItem] {
        var items: [MessageDisplayItem] = []
        var index = 0

        while index < messages.count {
            if let pair = comparisonPair(startingAt: index) {
                items.append(.comparisonPair(id: pair.left.turnId ?? pair.left.id, left: pair.left, right: pair.right))
                index += 2
            } else {
                items.append(.single(messages[index]))
                index += 1
            }
        }

        return items
    }

    private var projectThreads: [ChatThread] {
        chatStore.recentThreads(for: project.id)
    }

    private var isSending: Bool {
        chatStore.sendingThreadIds.contains(threadId)
    }

    private var liveActivity: ChatTurnActivity? {
        chatStore.activity(for: threadId)
    }

    private var isActiveChatTab: Bool {
        guard let activeTabId = store.activeTabId,
              let activeTab = store.tabsById[activeTabId] else {
            return false
        }

        return activeTab.chatThreadId == threadId && !store.sidebarFocused
    }

    private var currentProvider: ChatProvider {
        thread?.provider ?? .codex
    }

    private var selectedChatProvider: ChatProvider {
        if currentProvider == .secondOpinion {
            return thread?.lastChatProvider ?? .codex
        }

        return currentProvider
    }

    private var isPlanningMode: Bool {
        currentProvider == .secondOpinion
    }

    private var currentEffortLevel: EffortLevel {
        thread?.effortLevel ?? .high
    }

    private var currentPermissionLevel: PermissionLevel {
        thread?.permissionLevel ?? .readOnly
    }

    private var selectedPlanningFormat: PlanningFormat {
        thread?.planningFormat ?? .independent
    }

    private var selectedPlanningStrategy: SecondOpinionStrategy {
        thread?.secondOpinionStrategy ?? .independentFirst
    }

    private var selectedPlanningLeadOptions: [SecondOpinionStrategy] {
        [.codexFirst, .claudeFirst]
    }

    private var selectedPlanningRoute: PlanningRoute? {
        thread?.selectedPlanningRoute
    }

    private var availablePlanningRoutes: [PlanningRoute] {
        let codexAvailable = messages.contains { $0.role == .assistant && $0.participant == "Codex" }
        let claudeAvailable = messages.contains { $0.role == .assistant && $0.participant == "Claude" }
        let mergedAvailable = messages.contains { $0.role == .assistant && $0.participant == "Merged Plan" }

        var routes: [PlanningRoute] = []
        if codexAvailable { routes.append(.codex) }
        if claudeAvailable { routes.append(.claude) }
        if mergedAvailable || (codexAvailable && claudeAvailable) { routes.append(.merged) }
        return routes
    }

    private var bodyHasPlanningOutput: Bool {
        !availablePlanningRoutes.isEmpty
    }

    private var shouldShowInlinePlanningPanel: Bool {
        currentProvider == .secondOpinion && messages.isEmpty
    }

    private var planningFormatDescription: String {
        switch selectedPlanningFormat {
        case .independent:
            if messages.contains(where: { $0.layoutHint == .comparison }) {
                return "Independent plans are side by side below. Pick a route, then choose which agent should start execution."
            }
            return "Blink asks both agents for independent plans first so neither one anchors the other."
        case .critique:
            return selectedPlanningStrategy.statusText
        case .debate:
            if selectedPlanningStrategy == .claudeFirst {
                return "Claude proposes a plan, Codex challenges it, then Claude responds."
            }
            return "Codex proposes a plan, Claude challenges it, then Codex responds."
        case .synthesis:
            if selectedPlanningStrategy == .claudeFirst {
                return "Blink collects both plans independently, then asks Claude to synthesize them into one merged route."
            }
            return "Blink collects both plans independently, then asks Codex to synthesize them into one merged route."
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if showsHistorySidebar(for: proxy.size.width) {
                    historySidebar

                    Rectangle()
                        .fill(theme.border.opacity(0.8))
                        .frame(width: 1)
                }

                VStack(spacing: 0) {
                    if let error = thread?.lastError, !error.isEmpty {
                        errorBanner(error)
                    }

                    messageTimeline

                    if shouldShowInlinePlanningPanel {
                        planningSessionPanel
                    }

                    composer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(Color.clear)
        .onAppear {
            draft = chatStore.pendingPrompt(for: threadId)
            installKeyMonitor()
        }
        .onChange(of: threadId) { _, newThreadId in
            draft = chatStore.pendingPrompt(for: newThreadId)
            planningPanelError = nil
            pendingAttachments = []
            showModelMenu = false
            showCodexModelMenu = false
            showClaudeModelMenu = false
            showModeMenu = false
            showPlanningSettingsMenu = false
            showEffortMenu = false
            showPermissionMenu = false
        }
        .onChange(of: draft) { _, newValue in
            chatStore.setPendingPrompt(newValue, for: threadId)
        }
        .onDisappear {
            showModelMenu = false
            showCodexModelMenu = false
            showClaudeModelMenu = false
            showModeMenu = false
            showPlanningSettingsMenu = false
            showEffortMenu = false
            showPermissionMenu = false
            pendingAttachments = []
            removeKeyMonitor()
        }
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleAttachmentImport
        )
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: pendingDeletionBinding,
            titleVisibility: .visible,
            presenting: pendingDeletionThread
        ) { historyThread in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteThread(historyThread)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: { historyThread in
            Text("Delete \"\(historyThread.title.isEmpty ? historyThread.provider.displayName : historyThread.title)\" and its saved messages from Blink?")
        }
    }

    private func showsHistorySidebar(for availableWidth: CGFloat) -> Bool {
        availableWidth >= Layout.chatHistoryCollapseThreshold
    }

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)

                Spacer()

                Text("\(projectThreads.count)")
                    .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(projectThreads) { historyThread in
                        historyThreadRow(historyThread)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: Layout.chatHistoryRailWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.02))
    }

    private func historyThreadRow(_ historyThread: ChatThread) -> some View {
        let isSelected = historyThread.id == threadId
        let showDeleteControl = hoveredHistoryThreadId == historyThread.id || isSelected

        return ZStack(alignment: .topTrailing) {
            Button(action: { openThread(historyThread) }) {
                historyThreadRowLabel(historyThread, isSelected: isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .padding(.trailing, 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(hoveredHistoryThreadId == historyThread.id ? 0.06 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? theme.accent.opacity(0.85) : theme.border.opacity(0.85),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pointerCursor()

            Button(role: .destructive) {
                pendingDeletionThread = historyThread
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textDim)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Delete Conversation")
            .buttonStyle(.plain)
            .pointerCursor()
            .opacity(showDeleteControl ? 1 : 0)
            .allowsHitTesting(showDeleteControl)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .onHover { isHovering in
            hoveredHistoryThreadId = isHovering ? historyThread.id : (hoveredHistoryThreadId == historyThread.id ? nil : hoveredHistoryThreadId)
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletionThread = historyThread
            } label: {
                Label("Delete Conversation", systemImage: "trash")
            }
        }
    }

    private func historyThreadRowLabel(_ historyThread: ChatThread, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            historyThreadProviderIcon(provider: historyThread.provider, isSelected: isSelected)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(historyThread.title.isEmpty ? historyThread.provider.displayName : historyThread.title)
                    .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(historyThread.provider.displayName)
                        .lineLimit(1)

                    Text("•")

                    Text(historyTimestamp(for: historyThread.updatedAt))
                        .lineLimit(1)
                }
                .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyThreadProviderIcon(provider: ChatProvider, isSelected: Bool) -> some View {
        providerIcon(provider: provider, selected: isSelected)
            .frame(width: 16, height: 16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.danger)

            Text(message)
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.danger.opacity(0.08))
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayItems) { item in
                            switch item {
                            case .single(let message):
                                messageRow(message)
                                    .id(message.id)
                            case .comparisonPair(_, let left, let right):
                                comparisonRow(left: left, right: right)
                                    .id(left.turnId ?? left.id)
                            }
                        }
                    }

                    if isSending {
                        activityStrip
                            .id("activity-\(threadId)")
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .frame(maxWidth: Layout.chatContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToBottom(with: proxy)
            }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToBottom(with: proxy)
            }
            .onChange(of: isSending) { _, _ in
                scrollToBottom(with: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()

            Text(currentProvider == .secondOpinion ? "Start a planning session for this project" : "Ask anything about this project")
                .font(Fonts.primary(size: 15, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)

            Text(project.displayPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.textDim)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
    }

    private var planningSessionPanel: some View {
        planningSessionPanelContent
            .frame(maxWidth: Layout.chatContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 6)
    }

    private var planningSettingsPopover: some View {
        planningSessionPanelContent
            .padding(12)
            .frame(width: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.bg2.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.border.opacity(0.9), lineWidth: 1)
            )
    }

    private var planningSessionPanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Planning Session")
                .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)

            Text(planningFormatDescription)
                .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("Format")
                .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.textDim)

            adaptiveChipRow {
                ForEach(PlanningFormat.allCases, id: \.self) { format in
                    choiceChip(
                        title: format.displayName,
                        selected: selectedPlanningFormat == format
                    ) {
                        planningPanelError = nil
                        Task {
                            await chatStore.updateThreadPlanningFormat(format, for: threadId)
                        }
                    }
                }
            }

            if selectedPlanningFormat != .independent {
                Text(selectedPlanningFormat == .synthesis ? "Synthesizer" : "Lead")
                    .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)

                adaptiveChipRow {
                    ForEach(selectedPlanningLeadOptions, id: \.self) { strategy in
                        choiceChip(
                            title: strategy.displayName,
                            selected: selectedPlanningStrategy == strategy
                        ) {
                            planningPanelError = nil
                            Task {
                                await chatStore.updateThreadSecondOpinionStrategy(strategy, for: threadId)
                            }
                        }
                    }
                }
            }

            if bodyHasPlanningOutput {
                Text("Choose Route")
                    .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)

                adaptiveChipRow {
                    ForEach(availablePlanningRoutes, id: \.self) { route in
                        choiceChip(
                            title: route.displayName,
                            selected: selectedPlanningRoute == route
                        ) {
                            planningPanelError = nil
                            let nextRoute = selectedPlanningRoute == route ? nil : route
                            Task {
                                await chatStore.updateSelectedPlanningRoute(nextRoute, for: threadId)
                            }
                        }
                    }
                }
            }

            if let selectedPlanningRoute {
                Text("Start Next Phase")
                    .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)

                adaptiveChipRow {
                    handoffChip(title: "Implement With Codex", provider: .codex, route: selectedPlanningRoute)
                    handoffChip(title: "Implement With Claude", provider: .claude, route: selectedPlanningRoute)
                }
            }

            if let planningPanelError, !planningPanelError.isEmpty {
                Text(planningPanelError)
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func adaptiveChipRow<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content()
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(selected ? theme.bg : theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? theme.accent : Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? theme.accent : theme.border.opacity(0.9), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func handoffChip(title: String, provider: ChatProvider, route: PlanningRoute) -> some View {
        let isLaunching = launchingImplementationProvider == provider

        return Button(action: { launchImplementation(with: provider, route: route) }) {
            HStack(spacing: 6) {
                if isLaunching {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(theme.bg)
                } else {
                    providerIcon(provider: provider)
                        .frame(width: 14, height: 14)
                }

                Text(title)
                    .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
            }
            .foregroundStyle(theme.bg)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(launchingImplementationProvider != nil)
        .pointerCursor()
    }

    private var latestPendingRequestEvents: [ChatMessageRuntimeEvent] {
        for message in messages.reversed() where message.role == .assistant {
            let pendingEvents = chatStore.runtimeEvents(for: message.id)
                .filter {
                    ($0.kind == .approvalRequest || $0.kind == .userInputRequest)
                        && ($0.status == .pending || $0.status == .inProgress)
                }
            if !pendingEvents.isEmpty {
                return pendingEvents
            }
        }

        return []
    }

    private var composerPendingRequestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(latestPendingRequestEvents, id: \.id) { event in
                pendingRequestCard(event)
            }
        }
    }

    private func pendingRequestCard(_ event: ChatMessageRuntimeEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: event.kind == .approvalRequest ? "hand.raised.fill" : "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(event.kind == .approvalRequest ? theme.accent : theme.text)

                Text(event.kind == .approvalRequest ? "Approval Needed" : "Input Needed")
                    .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer(minLength: 0)
            }

            Text(event.title)
                .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                .foregroundStyle(theme.text)

            if let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                Text(detail)
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(event.questions, id: \.id) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.header)
                        .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.text)

                    Text(question.prompt)
                        .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !question.options.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(question.options, id: \.id) { option in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.label)
                                            .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                                            .foregroundStyle(theme.text)

                                        if let description = option.description, !description.isEmpty {
                                            Text(description)
                                                .font(Fonts.primary(size: 10, family: store.uiFontFamily))
                                                .foregroundStyle(theme.textDim)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(theme.border.opacity(0.85), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.82), lineWidth: 1)
        )
    }

    private var composerAttachmentStrip: some View {
        attachmentStrip(pendingAttachments, removable: true)
    }

    private func attachmentStrip(_ attachments: [ChatAttachment], removable: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment, removable: removable)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func attachmentChip(_ attachment: ChatAttachment, removable: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.isImage ? "photo" : "doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textDim)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(attachment.isImage ? "Image" : "File")
                    .font(Fonts.primary(size: 10, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
            }

            if removable {
                Button(action: { removePendingAttachment(attachment) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textDim)
                        .padding(2)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.border.opacity(0.85), lineWidth: 1)
        )
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user

        return Group {
            if isUser {
                userMessageBubble(message)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if message.role == .system {
                VStack(alignment: .leading, spacing: 6) {
                    if let participant = message.participant {
                        Text(participant)
                            .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                            .foregroundStyle(theme.accent)
                    }

                    Text(message.content)
                        .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.18), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let participant = message.participant {
                        Text(participant)
                            .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                            .foregroundStyle(theme.accent)
                    }

                    assistantMessageContent(message)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func userMessageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !message.attachments.isEmpty {
                attachmentStrip(message.attachments, removable: false)
            }

            let trimmedContent = trimmedMessageContent(message.content)
            if !trimmedContent.isEmpty {
                Text(trimmedContent)
                    .textSelection(.enabled)
                    .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    private func comparisonRow(left: ChatMessage, right: ChatMessage) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                comparisonCard(left)
                comparisonCard(right)
            }

            VStack(spacing: 12) {
                comparisonCard(left)
                comparisonCard(right)
            }
        }
    }

    private func comparisonCard(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let participant = message.participant {
                Text(participant)
                    .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.accent)
            }

            assistantMessageContent(message, insideComparison: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.border.opacity(0.9), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func assistantMessageContent(_ message: ChatMessage, insideComparison: Bool = false) -> some View {
        let runtimeEvents = chatStore.runtimeEvents(for: message.id)
        let workItems = runtimeEvents
            .filter { $0.kind == .commandExecution }
            .compactMap(\.workItem)
        let diffEvents = runtimeEvents.filter { $0.kind == .diffUpdate }
        let trimmedContent = trimmedMessageContent(message.content)

        VStack(alignment: .leading, spacing: 12) {
            if !workItems.isEmpty {
                compactWorkLog(workItems, messageId: message.id)
            }

            if !message.attachments.isEmpty {
                attachmentStrip(message.attachments, removable: false)
            }

            if isPlanningArtifact(message), !trimmedContent.isEmpty {
                planArtifactCard(message, insideComparison: insideComparison)
            } else if !trimmedContent.isEmpty {
                MarkdownText(content: message.content, project: project)
            }

            if !diffEvents.isEmpty {
                changedFilesCard(from: diffEvents)
            }
        }
    }

    @ViewBuilder
    private func planArtifactCard(_ message: ChatMessage, insideComparison: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(planArtifactTitle(for: message))
                    .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer(minLength: 0)

                Button(action: { copyToPasteboard(message.content) }) {
                    Text("Copy")
                        .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.textDim)
                        .textCase(.uppercase)
                        .tracking(1.1)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            MarkdownText(content: message.content, project: project)
        }

        if insideComparison {
            content
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.border.opacity(0.85), lineWidth: 1)
                )
        }
    }

    private func changedFilesCard(from events: [ChatMessageRuntimeEvent]) -> some View {
        let changedFiles = mergedChangedFiles(from: events)
        let summary = events
            .compactMap(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        let visibleFiles = Array(changedFiles.prefix(6))
        let overflowCount = max(changedFiles.count - visibleFiles.count, 0)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Changed Files")
                    .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
                    .textCase(.uppercase)
                    .tracking(1.2)

                if !changedFiles.isEmpty {
                    Text("(\(changedFiles.count))")
                        .font(Fonts.primary(size: 10, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.textDim)
                }

                Spacer(minLength: 0)
            }

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(Fonts.primary(size: 12, family: store.uiFontFamily))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleFiles.enumerated()), id: \.element.path) { index, file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textDim)
                            .frame(width: 14)

                        Text(file.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let additions = file.additions, let deletions = file.deletions {
                            Text("+\(additions)  -\(deletions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                    if index < visibleFiles.count - 1 {
                        Divider()
                            .overlay(theme.border.opacity(0.7))
                            .padding(.leading, 30)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )

            if overflowCount > 0 {
                Text("+\(overflowCount) more")
                    .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                    .foregroundStyle(theme.textDim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.82), lineWidth: 1)
        )
    }

    private func compactWorkLog(_ items: [ChatMessageWorkItem], messageId: String) -> some View {
        let isExpanded = expandedWorkLogMessageIds.contains(messageId)
        let hasOverflow = items.count > maxVisibleWorkLogItems
        let visibleItems = hasOverflow && !isExpanded ? Array(items.suffix(maxVisibleWorkLogItems)) : items
        let hiddenCount = max(items.count - visibleItems.count, 0)

        return VStack(alignment: .leading, spacing: 0) {
            if hasOverflow {
                HStack(spacing: 8) {
                    Text("Tool calls (\(items.count))")
                        .font(Fonts.primary(size: 9, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.textDim)
                        .textCase(.uppercase)
                        .tracking(1.4)

                    Spacer(minLength: 0)

                    Button(action: { toggleWorkLog(messageId: messageId) }) {
                        Text(isExpanded ? "Show less" : "Show \(hiddenCount) more")
                            .font(Fonts.primary(size: 9, weight: .medium, family: store.uiFontFamily))
                            .foregroundStyle(theme.textDim)
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 3)
            }

            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                compactWorkItemRow(item)

                if index < visibleItems.count - 1 {
                    Divider()
                        .overlay(theme.border.opacity(0.7))
                        .padding(.leading, 30)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.82), lineWidth: 1)
        )
        .padding(.bottom, 14)
    }

    private func compactWorkItemRow(_ item: ChatMessageWorkItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: workItemIconName(for: item))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(workItemTint(for: item))
                .frame(width: 16, height: 16)

            Text(compactWorkItemText(for: item))
                .textSelection(.enabled)
                .font(compactWorkItemFont(for: item))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func compactWorkItemText(for item: ChatMessageWorkItem) -> String {
        let heading = compactWorkItemHeading(for: item)

        if let preview = compactWorkItemPreview(for: item), !preview.isEmpty {
            return "\(heading) - \(preview)"
        }

        return heading
    }

    private func compactWorkItemHeading(for item: ChatMessageWorkItem) -> String {
        switch item.kind {
        case .commandExecution:
            "Command run"
        case .reasoning:
            "Reasoning"
        case .plan:
            "Plan updated"
        }
    }

    private func toggleWorkLog(messageId: String) {
        if expandedWorkLogMessageIds.contains(messageId) {
            expandedWorkLogMessageIds.remove(messageId)
        } else {
            expandedWorkLogMessageIds.insert(messageId)
        }
    }

    private func compactWorkItemPreview(for item: ChatMessageWorkItem) -> String? {
        switch item.kind {
        case .commandExecution:
            if let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                return detail
            }
            if let exitCode = item.exitCode {
                return "exit \(exitCode)"
            }
            return nil
        case .reasoning, .plan:
            if let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                return detail.replacingOccurrences(of: "\n", with: " ")
            }
            if let output = item.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output.replacingOccurrences(of: "\n", with: " ")
            }
            return nil
        }
    }

    private func workItemTint(for item: ChatMessageWorkItem) -> Color {
        switch item.status {
        case .inProgress:
            theme.accent
        case .failed:
            theme.danger
        case .completed:
            switch item.kind {
            case .commandExecution:
                theme.text
            case .reasoning, .plan:
                theme.accent
            }
        }
    }

    private func workItemIconName(for item: ChatMessageWorkItem) -> String {
        switch item.kind {
        case .commandExecution:
            switch item.status {
            case .inProgress:
                "terminal"
            case .completed:
                "checkmark.circle.fill"
            case .failed:
                "xmark.circle.fill"
            }
        case .reasoning:
            "lightbulb.fill"
        case .plan:
            "list.bullet.clipboard.fill"
        }
    }

    private func compactWorkItemFont(for item: ChatMessageWorkItem) -> Font {
        switch item.kind {
        case .commandExecution:
            .system(size: 12, design: .monospaced)
        case .reasoning, .plan:
            Fonts.primary(size: 12, family: store.uiFontFamily)
        }
    }

    private var activityStrip: some View {
        let activity = liveActivity ?? fallbackActivity

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ThinkingDots()
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title)
                        .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(theme.text)

                    if let detail = activity.detail, !detail.isEmpty {
                        Text(detail)
                            .font(Fonts.primary(size: 11, family: store.uiFontFamily))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            if !activity.steps.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(activity.steps) { step in
                            activityStepChip(step)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(activity.steps) { step in
                            activityStepChip(step)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.border.opacity(0.85), lineWidth: 1)
        )
        .frame(maxWidth: Layout.chatContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var fallbackActivity: ChatTurnActivity {
        if currentProvider == .secondOpinion {
            return ChatTurnActivity(
                title: "Planning Session",
                detail: "Running the current planning pass.",
                steps: []
            )
        }

        return ChatTurnActivity(
            title: "\(currentProvider.displayName) is replying",
            detail: "Working on your latest message.",
            steps: []
        )
    }

    private func activityStepChip(_ step: ChatTurnActivityStep) -> some View {
        let foreground: Color
        let background: Color
        let border: Color
        let iconName: String

        switch step.state {
        case .pending:
            foreground = theme.textDim
            background = Color.white.opacity(0.03)
            border = theme.border.opacity(0.75)
            iconName = "circle"
        case .active:
            foreground = theme.accent
            background = theme.accent.opacity(0.14)
            border = theme.accent.opacity(0.35)
            iconName = "smallcircle.filled.circle.fill"
        case .completed:
            foreground = theme.green
            background = theme.green.opacity(0.14)
            border = theme.green.opacity(0.35)
            iconName = "checkmark.circle.fill"
        }

        return HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(step.title)
                .font(Fonts.primary(size: 11, weight: .medium, family: store.uiFontFamily))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(background)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if !latestPendingRequestEvents.isEmpty {
                composerPendingRequestPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            if !pendingAttachments.isEmpty {
                composerAttachmentStrip
                    .padding(.horizontal, 16)
                    .padding(.top, latestPendingRequestEvents.isEmpty ? 16 : 12)
            }

            ComposerTextView(
                text: $draft,
                font: composerFont,
                textColor: NSColor(theme.text),
                placeholderString: composerPlaceholder,
                placeholderColor: NSColor(theme.textDim).withAlphaComponent(0.6),
                maxHeight: 200,
                onCommit: { send() },
                dynamicHeight: $editorHeight,
                isFocused: $composerFocused
            )
            .frame(height: editorHeight)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)

            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    composerControlRail
                        .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                Button(action: send) {
                    ZStack {
                        Circle()
                            .fill(canSend ? theme.accent.opacity(0.95) : theme.textDim.opacity(0.28))
                            .frame(width: 36, height: 36)

                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.bg)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.bg)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .pointerCursor()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(composerFocused ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    composerFocused ? theme.accent.opacity(0.65) : theme.border.opacity(0.9),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.16), value: composerFocused)
        .frame(maxWidth: Layout.chatContentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 24)
        .clipped()
    }

    private var composerControlRail: some View {
        HStack(spacing: 0) {
            Button(action: { showAttachmentImporter = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                    if !pendingAttachments.isEmpty {
                        Text("\(pendingAttachments.count)")
                            .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                    }
                }
                .foregroundStyle(pendingAttachments.isEmpty ? theme.textDim : theme.text)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .pointerCursor()

            railDivider
                .padding(.horizontal, 12)

            modelControls

            railDivider
                .padding(.horizontal, 12)

            if currentProvider.supportsEffort || currentProvider == .secondOpinion {
                Button(action: { showEffortMenu.toggle() }) {
                    HStack(spacing: 6) {
                        Text(currentEffortLevel.shortLabel)
                            .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.textDim)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerCursor()
                .backgroundPopover(isPresented: $showEffortMenu, placement: .aboveLeading) {
                    EffortLevelMenu(selectedLevel: currentEffortLevel) { level in
                        showEffortMenu = false
                        selectEffortLevel(level)
                    }
                }

                railDivider
                    .padding(.horizontal, 12)
            }

            Button(action: toggleModeMenu) {
                HStack(spacing: 6) {
                    Image(systemName: isPlanningMode ? "person.2.fill" : "bubble.left.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(isPlanningMode ? "Planning" : "Chat")
                        .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(theme.textDim)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .pointerCursor()
            .backgroundPopover(isPresented: $showModeMenu, placement: .aboveLeading) {
                ChatModeMenu(isPlanning: isPlanningMode) { planning in
                    showModeMenu = false
                    selectMode(isPlanning: planning)
                }
            }

            railDivider
                .padding(.horizontal, 12)

            if isPlanningMode {
                HStack(spacing: 6) {
                    Image(systemName: PermissionLevel.readOnly.iconName)
                        .font(.system(size: 11, weight: .medium))
                    Text(PermissionLevel.readOnly.displayName)
                        .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                }
                .foregroundStyle(theme.textDim)
                .fixedSize()
            } else {
                Button(action: { showPermissionMenu.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: currentPermissionLevel.iconName)
                            .font(.system(size: 11, weight: .medium))
                        Text(currentPermissionLevel.displayName)
                            .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.textDim)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerCursor()
                .backgroundPopover(isPresented: $showPermissionMenu, placement: .aboveLeading) {
                    PermissionLevelMenu(selectedLevel: currentPermissionLevel) { level in
                        showPermissionMenu = false
                        selectPermissionLevel(level)
                    }
                }
            }

            if isPlanningMode && !messages.isEmpty {
                railDivider
                    .padding(.horizontal, 12)

                Button(action: togglePlanningSettingsMenu) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Plan")
                            .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.textDim)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerCursor()
                .backgroundPopover(isPresented: $showPlanningSettingsMenu, placement: .aboveLeading) {
                    planningSettingsPopover
                }
            }
        }
    }

    @ViewBuilder
    private var modelControls: some View {
        if isPlanningMode {
            dualProviderModelControls
        } else {
            combinedProviderModelControl
        }
    }

    private var combinedProviderModelControl: some View {
        Button(action: { showModelMenu.toggle() }) {
            HStack(spacing: 6) {
                providerIcon(provider: selectedChatProvider)
                    .frame(width: 14, height: 14)
                Text(displayModelLabel(for: selectedChatProvider))
                    .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.textDim)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .pointerCursor()
        .backgroundPopover(isPresented: $showModelMenu, placement: .aboveLeading) {
            ChatProviderModelMenu(
                selectedProvider: selectedChatProvider,
                selectedModel: { provider in
                    resolvedModelSelection(for: provider)
                },
                modelOptions: { provider in
                    modelOptions(for: provider)
                },
                onSelect: { provider, model in
                    showModelMenu = false
                    selectProviderModel(provider: provider, model: model)
                }
            )
        }
    }

    private var dualProviderModelControls: some View {
        HStack(spacing: 10) {
            singleProviderModelControl(for: .codex, isPresented: $showCodexModelMenu)
            railDivider
                .frame(height: 16)
            singleProviderModelControl(for: .claude, isPresented: $showClaudeModelMenu)
        }
    }

    private func singleProviderModelControl(
        for provider: ChatProvider,
        isPresented: Binding<Bool>
    ) -> some View {
        Button(action: {
            isPresented.wrappedValue.toggle()
        }) {
            HStack(spacing: 6) {
                providerIcon(provider: provider)
                    .frame(width: 14, height: 14)
                Text(displayModelLabel(for: provider))
                    .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.textDim)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .pointerCursor()
        .backgroundPopover(isPresented: isPresented, placement: .aboveLeading) {
            ChatModelMenu(
                options: modelOptions(for: provider),
                selectedValue: resolvedModelSelection(for: provider),
                iconName: "sparkle",
                onSelect: { model in
                    isPresented.wrappedValue = false
                    selectModel(model, for: provider)
                }
            )
        }
    }

    private func displayModelLabel(for provider: ChatProvider) -> String {
        let resolved = resolvedModelSelection(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        return modelOptions(for: provider).first(where: { $0.value == resolved })?.label
            ?? (resolved.isEmpty ? provider.defaultModelLabel : resolved)
    }

    private var composerPlaceholder: String {
        if currentProvider == .secondOpinion {
            return messages.isEmpty
                ? "Ask for a plan for this project"
                : "Ask for another planning pass"
        }

        return messages.isEmpty
            ? "Ask about this project or request a change"
            : "Ask for follow-up changes"
    }

    private func modelOptions(for provider: ChatProvider) -> [(label: String, value: String)] {
        provider.composerTraits.modelOptions.map { ($0.label, $0.value) }
    }

    private func resolvedModelSelection(for provider: ChatProvider) -> String {
        let threadModel = thread?.model(for: provider).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard threadModel.isEmpty else { return threadModel }

        if provider == .codex {
            return store.chatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if provider == .claude {
            return store.claudeChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return store.chatModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var composerFont: NSFont {
        let family = store.uiFontFamily

        if family == Fonts.defaultFamily,
           let font = NSFont(name: "MesloLGSNFM-Regular", size: 13) {
            return font
        }

        return NSFont(name: family, size: 13)
            ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private var railDivider: some View {
        Rectangle()
            .fill(theme.border.opacity(0.75))
            .frame(width: 1, height: 18)
    }

    private var canSend: Bool {
        !isSending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    private func trimmedMessageContent(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPlanningArtifact(_ message: ChatMessage) -> Bool {
        message.role == .assistant && currentProvider == .secondOpinion
    }

    private func planArtifactTitle(for message: ChatMessage) -> String {
        switch message.participant {
        case "Codex":
            "Codex Plan"
        case "Claude":
            "Claude Plan"
        case "Merged Plan":
            "Merged Plan"
        default:
            "Proposed Plan"
        }
    }

    private func mergedChangedFiles(from events: [ChatMessageRuntimeEvent]) -> [ChatRuntimeDiffFile] {
        var filesByPath: [String: ChatRuntimeDiffFile] = [:]

        for event in events {
            for file in event.changedFiles {
                filesByPath[file.path] = file
            }
        }

        return filesByPath.values.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }

        let existingPaths = Set(pendingAttachments.map(\.path))
        let additions = urls
            .filter(\.isFileURL)
            .map(ChatAttachment.make(from:))
            .filter { !existingPaths.contains($0.path) }

        guard !additions.isEmpty else { return }
        pendingAttachments.append(contentsOf: additions)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func selectModel(_ model: String, for provider: ChatProvider) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if provider == .codex {
            store.chatModel = trimmedModel
        } else if provider == .claude {
            store.claudeChatModel = trimmedModel
        }

        Task {
            await chatStore.updateThreadModel(trimmedModel, for: threadId, provider: provider)
        }
    }

    private func selectProviderModel(provider: ChatProvider, model: String) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if provider == .codex {
            store.chatModel = trimmedModel
        } else if provider == .claude {
            store.claudeChatModel = trimmedModel
        }

        Task {
            if currentProvider != provider {
                await chatStore.updateThreadProvider(provider, for: threadId)
            }
            await chatStore.updateThreadModel(trimmedModel, for: threadId, provider: provider)
        }
    }

    private func selectMode(isPlanning: Bool) {
        let targetProvider: ChatProvider = isPlanning ? .secondOpinion : selectedChatProvider
        showPlanningSettingsMenu = false

        Task {
            await chatStore.updateThreadProvider(targetProvider, for: threadId)
        }
    }

    private func selectEffortLevel(_ level: EffortLevel) {
        Task {
            await chatStore.updateThreadEffortLevel(level, for: threadId)
        }
    }

    private func selectPermissionLevel(_ level: PermissionLevel) {
        Task {
            await chatStore.updateThreadPermissionLevel(level, for: threadId)
        }
    }

    private func toggleModeMenu() {
        showModeMenu.toggle()
    }

    private func togglePlanningSettingsMenu() {
        showPlanningSettingsMenu.toggle()
    }

    private func openThread(_ historyThread: ChatThread) {
        planningPanelError = nil
        showPlanningSettingsMenu = false
        store.replaceChatThread(in: tabId, with: historyThread.id, label: historyThread.title)
    }

    private var pendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletionThread != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionThread = nil
                }
            }
        )
    }

    private func deleteThread(_ historyThread: ChatThread) async {
        defer { pendingDeletionThread = nil }

        let threadTabs = store.projectTabs(for: project.id)
            .filter { $0.chatThreadId == historyThread.id }
            .map(\.id)
        let remainingThreads = projectThreads.filter { $0.id != historyThread.id }
        let isDeletingCurrentThread = historyThread.id == threadId

        if isDeletingCurrentThread {
            if let replacementThread = remainingThreads.first {
                store.openOrFocusChatTab(
                    projectId: project.id,
                    threadId: replacementThread.id,
                    label: replacementThread.title
                )
                for staleTabId in threadTabs {
                    store.closeTab(staleTabId)
                }
            } else {
                let replacementThread = await chatStore.createThread(
                    project: project,
                    model: resolvedModelSelection(for: historyThread.provider),
                    provider: historyThread.provider,
                    permissionLevel: historyThread.permissionLevel
                )
                store.replaceChatThread(in: tabId, with: replacementThread.id, label: replacementThread.title)
                for staleTabId in threadTabs where staleTabId != tabId {
                    store.closeTab(staleTabId)
                }
            }
        } else {
            for staleTabId in threadTabs {
                store.closeTab(staleTabId)
            }
        }

        await chatStore.deleteThread(historyThread.id)
    }

    private func historyTimestamp(for date: Date) -> String {
        Self.historyTimestampFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func send() {
        let outgoingDraft = draft
        let outgoingAttachments = pendingAttachments
        guard !outgoingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !outgoingAttachments.isEmpty else {
            return
        }

        draft = ""
        pendingAttachments = []
        chatStore.setPendingPrompt("", for: threadId)
        showPlanningSettingsMenu = false

        Task {
            do {
                let updatedThread = try await chatStore.sendMessage(
                    threadId: threadId,
                    project: project,
                    prompt: outgoingDraft,
                    attachments: outgoingAttachments,
                    fallbackModel: currentProvider == .claude ? "" : store.chatModel,
                    fallbackClaudeModel: isPlanningMode ? store.claudeChatModel : ""
                )
                store.setChatTabTitle(updatedThread.id, title: updatedThread.title)
            } catch {
                draft = outgoingDraft
                pendingAttachments = outgoingAttachments
                chatStore.setPendingPrompt(outgoingDraft, for: threadId)
            }
        }
    }

    private func launchImplementation(with provider: ChatProvider, route: PlanningRoute) {
        launchingImplementationProvider = provider
        planningPanelError = nil

        Task {
            do {
                await chatStore.updateSelectedPlanningRoute(route, for: threadId)
                let thread = try await chatStore.createImplementationThread(
                    from: threadId,
                    project: project,
                    provider: provider,
                    fallbackModel: provider == .codex ? store.chatModel : store.claudeChatModel
                )

                await MainActor.run {
                    store.openOrFocusChatTab(
                        projectId: project.id,
                        threadId: thread.id,
                        label: thread.title,
                        maximizeColumn: true
                    )
                    launchingImplementationProvider = nil
                }
            } catch {
                await MainActor.run {
                    planningPanelError = error.localizedDescription
                    launchingImplementationProvider = nil
                }
            }
        }
    }

    private static let historyTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard isActiveChatTab,
                  modifiers == [.command],
                  event.keyCode == 36 else {
                return event
            }

            guard canSend else { return nil }
            send()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func comparisonPair(startingAt index: Int) -> (left: ChatMessage, right: ChatMessage)? {
        guard index + 1 < messages.count else { return nil }

        let first = messages[index]
        let second = messages[index + 1]

        guard first.role == .assistant,
              second.role == .assistant,
              first.layoutHint == .comparison,
              second.layoutHint == .comparison,
              first.turnId == second.turnId,
              first.turnId != nil else {
            return nil
        }

        if first.participant == "Codex" {
            return (first, second)
        }

        if second.participant == "Codex" {
            return (second, first)
        }

        return (first, second)
    }

    @ViewBuilder
    private func providerIcon(provider: ChatProvider, selected: Bool = false) -> some View {
        switch provider {
        case .codex:
            BundledSVGIcon(name: "codex-icon")
        case .claude:
            ClaudeIcon()
        case .secondOpinion:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? theme.bg : theme.accent)
        }
    }
}

private struct ThinkingDots: View {
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { context in
            let activeIndex = Int(context.date.timeIntervalSinceReferenceDate * 3).quotientAndRemainder(dividingBy: 3).remainder

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(theme.accent.opacity(index == activeIndex ? 0.95 : 0.35))
                        .frame(width: 6, height: 6)
                        .scaleEffect(index == activeIndex ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.18), value: activeIndex)
                }
            }
            .frame(height: 10)
        }
    }
}
