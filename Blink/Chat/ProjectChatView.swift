import SwiftUI

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
    @State private var showProviderMenu = false
    @State private var showPlanningSettingsMenu = false
    @State private var launchingImplementationProvider: ChatProvider?
    @State private var planningPanelError: String?

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
        HStack(spacing: 0) {
            historySidebar

            Rectangle()
                .fill(theme.border.opacity(0.8))
                .frame(width: 1)

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
        .background(Color.clear)
        .onAppear {
            draft = chatStore.pendingPrompt(for: threadId)
            installKeyMonitor()
        }
        .onChange(of: threadId) { _, newThreadId in
            draft = chatStore.pendingPrompt(for: newThreadId)
            planningPanelError = nil
            showModelMenu = false
            showCodexModelMenu = false
            showClaudeModelMenu = false
            showProviderMenu = false
            showPlanningSettingsMenu = false
        }
        .onChange(of: draft) { _, newValue in
            chatStore.setPendingPrompt(newValue, for: threadId)
        }
        .onDisappear {
            showModelMenu = false
            showCodexModelMenu = false
            showClaudeModelMenu = false
            showProviderMenu = false
            showPlanningSettingsMenu = false
            removeKeyMonitor()
        }
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

        return Button(action: { openThread(historyThread) }) {
            HStack(alignment: .top, spacing: 10) {
                providerIcon(provider: historyThread.provider)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(historyThread.title.isEmpty ? historyThread.provider.displayName : historyThread.title)
                        .font(Fonts.primary(size: 12, weight: .medium, family: store.uiFontFamily))
                        .foregroundStyle(isSelected ? theme.bg : theme.text)
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
                    .foregroundStyle(isSelected ? theme.bg.opacity(0.72) : theme.textDim)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? theme.accent : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.accent : theme.border.opacity(0.85),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
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

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user

        return Group {
            if isUser {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(Fonts.primary(size: 13, family: store.uiFontFamily))
                    .foregroundStyle(theme.text)
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

                    MarkdownText(content: message.content)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

            MarkdownText(content: message.content)
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

            HStack(spacing: 0) {
                modelControls

                railDivider
                    .padding(.horizontal, 12)

                Button(action: toggleProviderMenu) {
                    HStack(spacing: 6) {
                        providerIcon(provider: currentProvider)
                            .frame(width: 14, height: 14)
                        Text(currentProvider.displayName)
                            .font(Fonts.primary(size: 13, weight: .medium, family: store.uiFontFamily))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.textDim)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerCursor()
                .backgroundPopover(isPresented: $showProviderMenu, placement: .aboveLeading) {
                    ChatProviderMenu(selectedProvider: currentProvider) { provider in
                        showProviderMenu = false
                        selectProvider(provider)
                    }
                }

                if currentProvider == .secondOpinion && !messages.isEmpty {
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

                Spacer()

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
    }

    @ViewBuilder
    private var modelControls: some View {
        if currentProvider == .secondOpinion {
            dualProviderModelControls
        } else {
            singleProviderModelControl(for: currentProvider, isPresented: $showModelMenu)
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
        switch provider {
        case .codex:
            [
                ("Codex Default", ""),
                ("GPT-5.4", "gpt-5.4"),
                ("GPT-5.3 Codex", "gpt-5.3-codex"),
                ("GPT-5.3 Codex Spark", "gpt-5.3-codex-spark"),
                ("GPT-5.2 Codex", "gpt-5.2-codex"),
                ("GPT-5.2", "gpt-5.2"),
            ]
        case .claude:
            [
                ("Claude Default", ""),
                ("Claude Opus 4.6", "opus"),
                ("Claude Sonnet 4.6", "sonnet"),
                ("Claude Haiku 4.5", "haiku"),
            ]
        case .secondOpinion:
            modelOptions(for: .codex)
        }
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
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func selectProvider(_ provider: ChatProvider) {
        Task {
            await chatStore.updateThreadProvider(provider, for: threadId)
        }
    }

    private func toggleProviderMenu() {
        showProviderMenu.toggle()
    }

    private func togglePlanningSettingsMenu() {
        showPlanningSettingsMenu.toggle()
    }

    private func openThread(_ historyThread: ChatThread) {
        planningPanelError = nil
        showPlanningSettingsMenu = false
        store.replaceChatThread(in: tabId, with: historyThread.id, label: historyThread.title)
    }

    private func historyTimestamp(for date: Date) -> String {
        Self.historyTimestampFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func send() {
        let outgoingDraft = draft
        guard !outgoingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        draft = ""
        chatStore.setPendingPrompt("", for: threadId)
        showPlanningSettingsMenu = false

        Task {
            do {
                let updatedThread = try await chatStore.sendMessage(
                    threadId: threadId,
                    project: project,
                    prompt: outgoingDraft,
                    fallbackModel: currentProvider == .claude ? "" : store.chatModel,
                    fallbackClaudeModel: currentProvider == .secondOpinion ? store.claudeChatModel : ""
                )
                store.setChatTabTitle(updatedThread.id, title: updatedThread.title)
            } catch {
                draft = outgoingDraft
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
    private func providerIcon(provider: ChatProvider) -> some View {
        switch provider {
        case .codex:
            BundledSVGIcon(name: "codex-icon")
        case .claude:
            ClaudeIcon()
        case .secondOpinion:
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
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
