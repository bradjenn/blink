import Foundation
import Observation

private enum SecondOpinionPrompts {
    private static let planningGuardrails = """
    This is a planning-only session:
    - Do not edit files.
    - Do not run commands.
    - Do not claim you already implemented anything.
    - Focus on analysis, tradeoffs, and a concrete next-step plan.
    """

    static func primaryPrompt(agentName: String, task: String) -> String {
        """
        You are \(agentName) replying inside a Blink Planning Session, a native terminal workspace for developers.

        The user asked:
        \(task)

        \(planningGuardrails)

        Reply like a teammate in chat:
        - Be direct and opinionated.
        - Use 2-4 short paragraphs.
        - No markdown headings.
        - Make your recommendation clear.
        """
    }

    static func critiquePrompt(
        agentName: String,
        originalTask: String,
        primaryAgentName: String,
        primaryMessage: String
    ) -> String {
        """
        You are \(agentName) contributing to a Blink Planning Session.

        Original user request:
        \(originalTask)

        \(primaryAgentName)'s answer:
        <<<PRIMARY_MESSAGE
        \(primaryMessage)
        PRIMARY_MESSAGE
        >>>

        Reply like a teammate leaning into the thread:
        - Use 2-4 short paragraphs.
        - No markdown headings.
        - Say where you agree and where you disagree.
        - Point out the most important thing \(primaryAgentName) missed or got wrong.
        - End with what you would actually recommend.
        """
    }

    static func rebuttalPrompt(
        agentName: String,
        originalTask: String,
        criticAgentName: String,
        criticMessage: String
    ) -> String {
        """
        You are \(agentName) replying in a Blink Planning Session debate.

        Original user request:
        \(originalTask)

        \(planningGuardrails)

        \(criticAgentName)'s critique:
        <<<CRITIQUE_MESSAGE
        \(criticMessage)
        CRITIQUE_MESSAGE
        >>>

        Reply like a teammate defending or adjusting the plan:
        - Use 2-3 short paragraphs.
        - No markdown headings.
        - State what you accept and what you reject from the critique.
        - End with your revised recommendation.
        """
    }

    static func synthesisPrompt(
        agentName: String,
        originalTask: String,
        codexMessage: String,
        claudeMessage: String
    ) -> String {
        """
        You are \(agentName) synthesizing a planning session inside Blink.

        Original user request:
        \(originalTask)

        \(planningGuardrails)

        Codex's plan:
        <<<CODEX_PLAN
        \(codexMessage)
        CODEX_PLAN
        >>>

        Claude's plan:
        <<<CLAUDE_PLAN
        \(claudeMessage)
        CLAUDE_PLAN
        >>>

        Produce the merged recommendation:
        - Use 2-4 short paragraphs.
        - No markdown headings.
        - Name the strongest idea from each plan.
        - Resolve the main disagreement.
        - End with one concrete plan Blink should follow.
        """
    }
}

enum ChatTurnActivityState: Equatable {
    case pending
    case active
    case completed
}

struct ChatTurnActivityStep: Identifiable, Equatable {
    let id: String
    let title: String
    let state: ChatTurnActivityState
}

struct ChatTurnActivity: Equatable {
    let title: String
    let detail: String?
    let steps: [ChatTurnActivityStep]
}

@MainActor @Observable
final class ChatStore {
    private(set) var threads: [ChatThread] = []
    private(set) var messagesByThreadId: [String: [ChatMessage]] = [:]
    private(set) var runtimeEventsByMessageId: [String: [ChatMessageRuntimeEvent]] = [:]
    private(set) var sendingThreadIds: Set<String> = []
    private(set) var activityByThreadId: [String: ChatTurnActivity] = [:]
    private(set) var loaded = false

    private let persistence = ChatPersistence()
    private let codexService = CodexCLIService()
    private let claudeService = ClaudeCLIService()

    func load() async {
        guard !loaded else { return }

        do {
            let snapshot = try await persistence.load()
            threads = snapshot.threads.sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.createdAt > right.createdAt
                }
                return left.updatedAt > right.updatedAt
            }
            messagesByThreadId = Dictionary(grouping: snapshot.messages, by: \.threadId)
            for threadId in messagesByThreadId.keys {
                messagesByThreadId[threadId]?.sort { $0.createdAt < $1.createdAt }
            }
            runtimeEventsByMessageId = Dictionary(grouping: snapshot.runtimeEvents, by: \.messageId)
            for messageId in runtimeEventsByMessageId.keys {
                runtimeEventsByMessageId[messageId]?.sort { left, right in
                    if left.createdAt == right.createdAt {
                        return left.id < right.id
                    }
                    return left.createdAt < right.createdAt
                }
            }
        } catch {
            threads = []
            messagesByThreadId = [:]
            runtimeEventsByMessageId = [:]
        }

        loaded = true
    }

    func thread(_ threadId: String) -> ChatThread? {
        threads.first(where: { $0.id == threadId })
    }

    func messages(for threadId: String) -> [ChatMessage] {
        messagesByThreadId[threadId] ?? []
    }

    func workItems(for messageId: String) -> [ChatMessageWorkItem] {
        runtimeEvents(for: messageId).compactMap(\.workItem)
    }

    func runtimeEvents(for messageId: String) -> [ChatMessageRuntimeEvent] {
        runtimeEventsByMessageId[messageId] ?? []
    }

    func activity(for threadId: String) -> ChatTurnActivity? {
        activityByThreadId[threadId]
    }

    func recentThreads(for projectId: String, provider: ChatProvider? = nil) -> [ChatThread] {
        threads
            .filter { thread in
                thread.projectId == projectId && (provider == nil || thread.provider == provider)
            }
            .sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.createdAt > right.createdAt
                }
                return left.updatedAt > right.updatedAt
            }
    }

    func mostRecentThread(for projectId: String, provider: ChatProvider? = nil) -> ChatThread? {
        recentThreads(for: projectId, provider: provider).first
    }

    func ensureThread(
        for project: Project,
        model: String,
        provider: ChatProvider = .codex
    ) async -> ChatThread {
        if let existing = mostRecentThread(for: project.id, provider: provider) {
            return existing
        }

        return await createThread(project: project, model: model, provider: provider)
    }

    func createThread(
        project: Project,
        model: String,
        provider: ChatProvider = .codex,
        permissionLevel: PermissionLevel = .readOnly
    ) async -> ChatThread {
        let now = Date()
        var thread = ChatThread(
            id: UUID().uuidString,
            projectId: project.id,
            title: defaultTitle(for: provider),
            provider: provider,
            lastChatProvider: provider == .secondOpinion ? .codex : provider,
            planningFormat: .independent,
            secondOpinionStrategy: .independentFirst,
            model: model,
            providerModels: [:],
            providerSessionIds: [:],
            providerBootstrapSummaries: [:],
            permissionLevel: permissionLevel,
            lastError: nil,
            createdAt: now,
            updatedAt: now
        )
        thread.setModel(model, for: provider == .secondOpinion ? .codex : provider)
        threads.insert(thread, at: 0)
        await persist()
        return thread
    }

    func deleteThread(_ threadId: String) async {
        let messageIds = Set(messages(for: threadId).map(\.id))
        threads.removeAll { $0.id == threadId }
        messagesByThreadId[threadId] = nil
        for messageId in messageIds {
            runtimeEventsByMessageId[messageId] = nil
        }
        sendingThreadIds.remove(threadId)
        activityByThreadId[threadId] = nil
        await persist()
    }

    func updateThreadModel(_ model: String, for threadId: String, provider: ChatProvider) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard threads[index].model(for: provider) != trimmedModel else { return }

        threads[index].setModel(trimmedModel, for: provider)
        await persist()
    }

    func updateThreadEffortLevel(_ level: EffortLevel, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].effortLevel != level else { return }

        threads[index].effortLevel = level
        threads[index].updatedAt = Date()
        await persist()
    }

    func updateThreadPermissionLevel(_ level: PermissionLevel, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].permissionLevel != level else { return }

        threads[index].permissionLevel = level
        threads[index].updatedAt = Date()
        await persist()
    }

    func updateThreadSecondOpinionStrategy(_ strategy: SecondOpinionStrategy, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].secondOpinionStrategy != strategy else { return }

        threads[index].secondOpinionStrategy = strategy
        threads[index].updatedAt = Date()
        await persist()
    }

    func updateThreadPlanningFormat(_ format: PlanningFormat, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].planningFormat != format else { return }

        threads[index].planningFormat = format
        if format == .independent {
            threads[index].secondOpinionStrategy = .independentFirst
        } else if threads[index].secondOpinionStrategy == .independentFirst {
            threads[index].secondOpinionStrategy = .codexFirst
        }
        threads[index].selectedPlanningRoute = nil
        threads[index].updatedAt = Date()
        await persist()
    }

    func updateSelectedPlanningRoute(_ route: PlanningRoute?, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].selectedPlanningRoute != route else { return }

        threads[index].selectedPlanningRoute = route
        threads[index].updatedAt = Date()
        await persist()
    }

    func createImplementationThread(
        from planningThreadId: String,
        project: Project,
        provider: ChatProvider,
        fallbackModel: String
    ) async throws -> ChatThread {
        guard provider == .codex || provider == .claude else {
            throw ChatProviderError.invalidRequest("Planning handoff can only launch Codex or Claude implementation chats.")
        }
        guard let planningThread = thread(planningThreadId) else {
            throw ChatProviderError.invalidRequest("Planning session not found.")
        }

        let resolvedModel = resolvedModelForSend(
            thread: planningThread,
            provider: provider,
            fallbackModel: fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let executionThread = await createThread(
            project: project,
            model: resolvedModel,
            provider: provider,
            permissionLevel: planningThread.permissionLevel
        )

        if let executionIndex = threads.firstIndex(where: { $0.id == executionThread.id }) {
            let bootstrap = buildImplementationBootstrapSummary(
                planningThreadId: planningThreadId,
                project: project,
                route: planningThread.selectedPlanningRoute
            )
            threads[executionIndex].setBootstrapSummary(bootstrap.isEmpty ? nil : bootstrap, for: provider)
            await persist()
        }

        let starterPrompt = buildImplementationStarterPrompt(
            project: project,
            route: planningThread.selectedPlanningRoute
        )
        setPendingPrompt(starterPrompt, for: executionThread.id)
        return thread(executionThread.id) ?? executionThread
    }

    func updateThreadProvider(_ provider: ChatProvider, for threadId: String) async {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].provider != provider else { return }

        if threads[index].sessionId(for: provider) == nil {
            let summary = buildBootstrapSummary(for: threadId, targetProvider: provider)
            threads[index].setBootstrapSummary(summary.isEmpty ? nil : summary, for: provider)
        }

        threads[index].setActiveProvider(provider)
        threads[index].lastError = nil
        if isDefaultTitle(threads[index].title) {
            threads[index].title = defaultTitle(for: provider)
        }
        await persist()
    }

    func sendMessage(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment] = [],
        fallbackModel: String,
        fallbackClaudeModel: String = ""
    ) async throws -> ChatThread {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatProviderError.invalidRequest("Chat thread not found.")
        }
        guard !sendingThreadIds.contains(threadId) else {
            throw ChatProviderError.invalidRequest("This chat is already sending a message.")
        }

        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !attachments.isEmpty else {
            throw ChatProviderError.invalidRequest("Message cannot be empty.")
        }

        let fallbackModel = fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackClaudeModel = fallbackClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeProvider = threads[index].provider
        let primaryProvider = activeProvider == .secondOpinion ? ChatProvider.codex : activeProvider
        let resolvedModel = resolvedModelForSend(
            thread: threads[index],
            provider: primaryProvider,
            fallbackModel: fallbackModel
        )
        let resolvedClaudeModel = activeProvider == .secondOpinion
            ? resolvedModelForSend(
                thread: threads[index],
                provider: .claude,
                fallbackModel: fallbackClaudeModel
            )
            : ""

        threads[index].setModel(resolvedModel, for: primaryProvider)
        if activeProvider == .secondOpinion {
            threads[index].setModel(resolvedClaudeModel, for: .claude)
            threads[index].selectedPlanningRoute = nil
        }
        threads[index].lastError = nil
        sendingThreadIds.insert(threadId)
        if activeProvider == .secondOpinion {
            setActivity(
                for: threadId,
                title: "Planning Session",
                detail: "Preparing the planning run."
            )
        } else {
            setActivity(
                for: threadId,
                title: "\(activeProvider.displayName) is replying",
                detail: "Preparing a response for this project.",
                stepTitles: ["Draft response"],
                activeStepIndex: 0
            )
        }
        defer {
            sendingThreadIds.remove(threadId)
            activityByThreadId[threadId] = nil
        }

        let userMessage = appendMessage(
            threadId: threadId,
            role: .user,
            content: prompt,
            attachments: attachments
        )
        if !prompt.isEmpty, threads[index].title == defaultTitle(for: threads[index].provider) {
            threads[index].title = Self.title(from: prompt)
        }
        threads[index].updatedAt = userMessage.createdAt
        await persist()

        do {
            switch threads[index].provider {
            case .codex, .claude:
                return try await runSingleProviderTurn(
                    provider: threads[index].provider,
                    threadId: threadId,
                    project: project,
                    prompt: prompt,
                    model: resolvedModel,
                    attachments: attachments
                )
            case .secondOpinion:
                return try await runSecondOpinionTurn(
                    threadId: threadId,
                    project: project,
                    prompt: prompt,
                    attachments: attachments,
                    codexModel: resolvedModel,
                    claudeModel: resolvedClaudeModel,
                    format: threads[index].planningFormat,
                    strategy: threads[index].secondOpinionStrategy
                )
            }
        } catch {
            if let latestIndex = threads.firstIndex(where: { $0.id == threadId }) {
                threads[latestIndex].lastError = error.localizedDescription
                threads[latestIndex].updatedAt = Date()
                await persist()
            }
            throw error
        }
    }

    func setPendingPrompt(_ prompt: String, for threadId: String) {
        pendingPromptByThreadId[threadId] = prompt
    }

    func pendingPrompt(for threadId: String) -> String {
        pendingPromptByThreadId[threadId] ?? ""
    }

    private var pendingPromptByThreadId: [String: String] = [:]

    private func runSingleProviderTurn(
        provider: ChatProvider,
        threadId: String,
        project: Project,
        prompt: String,
        model: String,
        attachments: [ChatAttachment]
    ) async throws -> ChatThread {
        guard let currentThread = thread(threadId) else {
            throw ChatProviderError.invalidRequest("Chat thread not found.")
        }

        let effectivePrompt = bootstrapPromptIfNeeded(
            thread: currentThread,
            provider: provider,
            prompt: promptWithAttachmentContext(prompt, attachments: attachments)
        )

        let effort = provider.supportsEffort ? currentThread.effortLevel.cliValue : nil

        let result = try await sendTurn(
            provider: provider,
            projectPath: project.path,
            model: model,
            sessionId: currentThread.providerSessionId,
            prompt: effectivePrompt,
            effort: effort,
            permissionLevel: currentThread.permissionLevel,
            attachments: attachments
        )

        return try await applyProviderResult(
            provider: provider,
            result: result,
            to: threadId
        )
    }

    private func runSecondOpinionTurn(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment],
        codexModel: String,
        claudeModel: String,
        format: PlanningFormat,
        strategy: SecondOpinionStrategy
    ) async throws -> ChatThread {
        let turnId = UUID().uuidString

        switch format {
        case .independent:
            return try await runIndependentSecondOpinionTurn(
                threadId: threadId,
                project: project,
                prompt: promptWithAttachmentContext(prompt, attachments: attachments),
                attachments: attachments,
                codexModel: codexModel,
                claudeModel: claudeModel,
                turnId: turnId
            )
        case .critique:
            return try await runSequentialCritiqueTurn(
                threadId: threadId,
                project: project,
                prompt: promptWithAttachmentContext(prompt, attachments: attachments),
                attachments: attachments,
                turnId: turnId,
                strategy: strategy,
                codexModel: codexModel,
                claudeModel: claudeModel
            )
        case .debate:
            return try await runDebateTurn(
                threadId: threadId,
                project: project,
                prompt: promptWithAttachmentContext(prompt, attachments: attachments),
                attachments: attachments,
                turnId: turnId,
                strategy: strategy,
                codexModel: codexModel,
                claudeModel: claudeModel
            )
        case .synthesis:
            return try await runSynthesisTurn(
                threadId: threadId,
                project: project,
                prompt: promptWithAttachmentContext(prompt, attachments: attachments),
                attachments: attachments,
                turnId: turnId,
                strategy: strategy,
                codexModel: codexModel,
                claudeModel: claudeModel
            )
        }
    }

    private func runIndependentSecondOpinionTurn(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment],
        codexModel: String,
        claudeModel: String,
        turnId: String
    ) async throws -> ChatThread {
        setActivity(
            for: threadId,
            title: "Planning Session · Independent",
            detail: "Collecting separate plans before either agent sees the other.",
            stepTitles: ["Codex plan", "Claude plan"],
            activeStepIndex: 0
        )
        _ = appendMessage(
            threadId: threadId,
            role: .system,
            content: "Blink is collecting independent first takes from Codex and Claude.",
            participant: "Blink",
            turnId: turnId
        )
        await persist()

        var codexResult: ChatTurnResult?
        var claudeResult: ChatTurnResult?
        var codexError: Error?
        var claudeError: Error?

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            codexResult = try await sendTurn(
                provider: .codex,
                projectPath: project.path,
                model: codexModel,
                sessionId: currentThread.sessionId(for: .codex),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: .codex,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: "Codex", task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
        } catch {
            codexError = error
        }

        setActivity(
            for: threadId,
            title: "Planning Session · Independent",
            detail: "Waiting for Claude's independent plan.",
            stepTitles: ["Codex plan", "Claude plan"],
            activeStepIndex: 1
        )

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            claudeResult = try await sendTurn(
                provider: .claude,
                projectPath: project.path,
                model: claudeModel,
                sessionId: currentThread.sessionId(for: .claude),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: .claude,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: "Claude", task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
        } catch {
            claudeError = error
        }

        let renderAsComparison = codexResult != nil && claudeResult != nil
        var gotAtLeastOneResponse = false

        if let codexResult {
            gotAtLeastOneResponse = true
            _ = try await applyProviderResult(
                provider: .codex,
                result: codexResult,
                to: threadId,
                participant: "Codex",
                turnId: turnId,
                layoutHint: renderAsComparison ? .comparison : nil
            )
        }

        if let claudeResult {
            gotAtLeastOneResponse = true
            _ = try await applyProviderResult(
                provider: .claude,
                result: claudeResult,
                to: threadId,
                participant: "Claude",
                turnId: turnId,
                layoutHint: renderAsComparison ? .comparison : nil
            )
        }

        if let codexError {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "Codex could not deliver an independent answer: \(codexError.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if let claudeError {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "Claude could not deliver an independent answer: \(claudeError.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if !gotAtLeastOneResponse {
            throw ChatProviderError.executionFailed("Planning Session could not get a response from Codex or Claude.")
        }

        let completionText = renderAsComparison
            ? "Independent first takes are ready. Pick a lead if you want future turns to anchor on one side."
            : "Planning pass complete."
        return try await finishSecondOpinionTurn(threadId: threadId, turnId: turnId, content: completionText)
    }

    private func runSequentialCritiqueTurn(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment],
        turnId: String,
        strategy: SecondOpinionStrategy,
        codexModel: String,
        claudeModel: String
    ) async throws -> ChatThread {
        let (primaryProvider, secondaryProvider) = orderedProviders(for: strategy)
        let primaryModel = model(for: primaryProvider, codexModel: codexModel, claudeModel: claudeModel)
        let secondaryModel = model(for: secondaryProvider, codexModel: codexModel, claudeModel: claudeModel)
        let primaryName = participantName(for: primaryProvider)
        let secondaryName = participantName(for: secondaryProvider)
        let stepTitles = ["\(primaryName) plan", "\(secondaryName) critique"]

        setActivity(
            for: threadId,
            title: "Planning Session · Critique",
            detail: "Waiting for \(primaryName)'s opening plan.",
            stepTitles: stepTitles,
            activeStepIndex: 0
        )

        _ = appendMessage(
            threadId: threadId,
            role: .system,
            content: "Blink is asking \(primaryName) first, then \(secondaryName) for a planning follow-up.",
            participant: "Blink",
            turnId: turnId
        )
        await persist()

        var primaryResponse: String?
        var gotAtLeastOneResponse = false

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            let result = try await sendTurn(
                provider: primaryProvider,
                projectPath: project.path,
                model: primaryModel,
                sessionId: currentThread.sessionId(for: primaryProvider),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: primaryProvider,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: primaryName, task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
            gotAtLeastOneResponse = true
            primaryResponse = result.text
            _ = try await applyProviderResult(
                provider: primaryProvider,
                result: result,
                to: threadId,
                participant: primaryName,
                turnId: turnId
            )
        } catch {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "\(primaryName) could not deliver the primary answer: \(error.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        setActivity(
            for: threadId,
            title: "Planning Session · Critique",
            detail: "Waiting for \(secondaryName)'s critique.",
            stepTitles: stepTitles,
            activeStepIndex: 1
        )

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            let secondOpinionPrompt: String
            if let primaryResponse {
                secondOpinionPrompt = bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: secondaryProvider,
                    prompt: SecondOpinionPrompts.critiquePrompt(
                        agentName: secondaryName,
                        originalTask: prompt,
                        primaryAgentName: primaryName,
                        primaryMessage: primaryResponse
                    )
                )
            } else {
                secondOpinionPrompt = bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: secondaryProvider,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: secondaryName, task: prompt)
                )
            }

            let result = try await sendTurn(
                provider: secondaryProvider,
                projectPath: project.path,
                model: secondaryModel,
                sessionId: currentThread.sessionId(for: secondaryProvider),
                prompt: secondOpinionPrompt,
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
            gotAtLeastOneResponse = true
            _ = try await applyProviderResult(
                provider: secondaryProvider,
                result: result,
                to: threadId,
                participant: secondaryName,
                turnId: turnId
            )
        } catch {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "\(secondaryName) could not deliver the planning follow-up: \(error.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if !gotAtLeastOneResponse {
            throw ChatProviderError.executionFailed("Planning Session could not get a response from Codex or Claude.")
        }

        return try await finishSecondOpinionTurn(threadId: threadId, turnId: turnId, content: "Planning pass complete.")
    }

    private func runDebateTurn(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment],
        turnId: String,
        strategy: SecondOpinionStrategy,
        codexModel: String,
        claudeModel: String
    ) async throws -> ChatThread {
        let (primaryProvider, secondaryProvider) = orderedProviders(for: strategy)
        let primaryModel = model(for: primaryProvider, codexModel: codexModel, claudeModel: claudeModel)
        let secondaryModel = model(for: secondaryProvider, codexModel: codexModel, claudeModel: claudeModel)
        let primaryName = participantName(for: primaryProvider)
        let secondaryName = participantName(for: secondaryProvider)
        let stepTitles = ["\(primaryName) plan", "\(secondaryName) critique", "\(primaryName) rebuttal"]

        setActivity(
            for: threadId,
            title: "Planning Session · Debate",
            detail: "Waiting for \(primaryName)'s opening plan.",
            stepTitles: stepTitles,
            activeStepIndex: 0
        )

        _ = appendMessage(
            threadId: threadId,
            role: .system,
            content: "Blink is running a planning debate: \(primaryName) proposes, \(secondaryName) critiques, then \(primaryName) responds.",
            participant: "Blink",
            turnId: turnId
        )
        await persist()

        var primaryResponse: String?
        var secondaryResponse: String?
        var gotAtLeastOneResponse = false

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            let result = try await sendTurn(
                provider: primaryProvider,
                projectPath: project.path,
                model: primaryModel,
                sessionId: currentThread.sessionId(for: primaryProvider),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: primaryProvider,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: primaryName, task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
            gotAtLeastOneResponse = true
            primaryResponse = result.text
            _ = try await applyProviderResult(
                provider: primaryProvider,
                result: result,
                to: threadId,
                participant: primaryName,
                turnId: turnId
            )
        } catch {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "\(primaryName) could not deliver the opening plan: \(error.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        setActivity(
            for: threadId,
            title: "Planning Session · Debate",
            detail: "Waiting for \(secondaryName)'s critique.",
            stepTitles: stepTitles,
            activeStepIndex: 1
        )

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            let critiquePrompt: String
            if let primaryResponse {
                critiquePrompt = bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: secondaryProvider,
                    prompt: SecondOpinionPrompts.critiquePrompt(
                        agentName: secondaryName,
                        originalTask: prompt,
                        primaryAgentName: primaryName,
                        primaryMessage: primaryResponse
                    )
                )
            } else {
                critiquePrompt = bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: secondaryProvider,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: secondaryName, task: prompt)
                )
            }

            let result = try await sendTurn(
                provider: secondaryProvider,
                projectPath: project.path,
                model: secondaryModel,
                sessionId: currentThread.sessionId(for: secondaryProvider),
                prompt: critiquePrompt,
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
            gotAtLeastOneResponse = true
            secondaryResponse = result.text
            _ = try await applyProviderResult(
                provider: secondaryProvider,
                result: result,
                to: threadId,
                participant: secondaryName,
                turnId: turnId
            )
        } catch {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "\(secondaryName) could not deliver the critique: \(error.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if let secondaryResponse {
            do {
                guard let currentThread = thread(threadId) else {
                    throw ChatProviderError.invalidRequest("Chat thread not found.")
                }
                setActivity(
                    for: threadId,
                    title: "Planning Session · Debate",
                    detail: "Waiting for \(primaryName)'s rebuttal.",
                    stepTitles: stepTitles,
                    activeStepIndex: 2
                )
                let result = try await sendTurn(
                    provider: primaryProvider,
                    projectPath: project.path,
                    model: primaryModel,
                    sessionId: currentThread.sessionId(for: primaryProvider),
                    prompt: bootstrapPromptIfNeeded(
                        thread: currentThread,
                        provider: primaryProvider,
                        prompt: SecondOpinionPrompts.rebuttalPrompt(
                            agentName: primaryName,
                            originalTask: prompt,
                            criticAgentName: secondaryName,
                            criticMessage: secondaryResponse
                        )
                    ),
                    effort: currentThread.effortLevel.cliValue,
                    permissionLevel: .readOnly,
                    attachments: attachments
                )
                gotAtLeastOneResponse = true
                _ = try await applyProviderResult(
                    provider: primaryProvider,
                    result: result,
                    to: threadId,
                    participant: primaryName,
                    turnId: turnId
                )
            } catch {
                _ = appendMessage(
                    threadId: threadId,
                    role: .system,
                    content: "\(primaryName) could not deliver the rebuttal: \(error.localizedDescription)",
                    participant: "Blink",
                    turnId: turnId
                )
                await persist()
            }
        }

        if !gotAtLeastOneResponse {
            throw ChatProviderError.executionFailed("Planning Session could not get a response from Codex or Claude.")
        }

        return try await finishSecondOpinionTurn(threadId: threadId, turnId: turnId, content: "Debate complete.")
    }

    private func runSynthesisTurn(
        threadId: String,
        project: Project,
        prompt: String,
        attachments: [ChatAttachment],
        turnId: String,
        strategy: SecondOpinionStrategy,
        codexModel: String,
        claudeModel: String
    ) async throws -> ChatThread {
        let synthesizerProvider: ChatProvider = strategy == .claudeFirst ? .claude : .codex
        let synthesizerName = participantName(for: synthesizerProvider)
        let stepTitles = ["Codex plan", "Claude plan", "\(synthesizerName) merge"]

        setActivity(
            for: threadId,
            title: "Planning Session · Synthesis",
            detail: "Collecting Codex's independent plan.",
            stepTitles: stepTitles,
            activeStepIndex: 0
        )

        _ = appendMessage(
            threadId: threadId,
            role: .system,
            content: "Blink is collecting independent plans, then asking \(synthesizerName) to synthesize them.",
            participant: "Blink",
            turnId: turnId
        )
        await persist()

        var codexResult: ChatTurnResult?
        var claudeResult: ChatTurnResult?
        var codexError: Error?
        var claudeError: Error?

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            codexResult = try await sendTurn(
                provider: .codex,
                projectPath: project.path,
                model: codexModel,
                sessionId: currentThread.sessionId(for: .codex),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: .codex,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: "Codex", task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
        } catch {
            codexError = error
        }

        setActivity(
            for: threadId,
            title: "Planning Session · Synthesis",
            detail: "Collecting Claude's independent plan.",
            stepTitles: stepTitles,
            activeStepIndex: 1
        )

        do {
            guard let currentThread = thread(threadId) else {
                throw ChatProviderError.invalidRequest("Chat thread not found.")
            }
            claudeResult = try await sendTurn(
                provider: .claude,
                projectPath: project.path,
                model: claudeModel,
                sessionId: currentThread.sessionId(for: .claude),
                prompt: bootstrapPromptIfNeeded(
                    thread: currentThread,
                    provider: .claude,
                    prompt: SecondOpinionPrompts.primaryPrompt(agentName: "Claude", task: prompt)
                ),
                effort: currentThread.effortLevel.cliValue,
                permissionLevel: .readOnly,
                attachments: attachments
            )
        } catch {
            claudeError = error
        }

        let renderAsComparison = codexResult != nil && claudeResult != nil
        var gotAtLeastOneResponse = false

        if let codexResult {
            gotAtLeastOneResponse = true
            _ = try await applyProviderResult(
                provider: .codex,
                result: codexResult,
                to: threadId,
                participant: "Codex",
                turnId: turnId,
                layoutHint: renderAsComparison ? .comparison : nil
            )
        }

        if let claudeResult {
            gotAtLeastOneResponse = true
            _ = try await applyProviderResult(
                provider: .claude,
                result: claudeResult,
                to: threadId,
                participant: "Claude",
                turnId: turnId,
                layoutHint: renderAsComparison ? .comparison : nil
            )
        }

        if let codexError {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "Codex could not deliver an independent answer: \(codexError.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if let claudeError {
            _ = appendMessage(
                threadId: threadId,
                role: .system,
                content: "Claude could not deliver an independent answer: \(claudeError.localizedDescription)",
                participant: "Blink",
                turnId: turnId
            )
            await persist()
        }

        if let codexPlan = codexResult?.text,
           let claudePlan = claudeResult?.text {
            do {
                guard let currentThread = thread(threadId) else {
                    throw ChatProviderError.invalidRequest("Chat thread not found.")
                }
                let synthesisModel = model(for: synthesizerProvider, codexModel: codexModel, claudeModel: claudeModel)
                setActivity(
                    for: threadId,
                    title: "Planning Session · Synthesis",
                    detail: "Waiting for \(synthesizerName) to merge the two plans.",
                    stepTitles: stepTitles,
                    activeStepIndex: 2
                )
                let result = try await sendTurn(
                    provider: synthesizerProvider,
                    projectPath: project.path,
                    model: synthesisModel,
                    sessionId: currentThread.sessionId(for: synthesizerProvider),
                    prompt: bootstrapPromptIfNeeded(
                        thread: currentThread,
                        provider: synthesizerProvider,
                        prompt: SecondOpinionPrompts.synthesisPrompt(
                            agentName: synthesizerName,
                            originalTask: prompt,
                            codexMessage: codexPlan,
                            claudeMessage: claudePlan
                        )
                    ),
                    effort: currentThread.effortLevel.cliValue,
                    permissionLevel: .readOnly,
                    attachments: attachments
                )
                gotAtLeastOneResponse = true
                _ = try await applyProviderResult(
                    provider: synthesizerProvider,
                    result: result,
                    to: threadId,
                    participant: "Merged Plan",
                    turnId: turnId
                )
            } catch {
                _ = appendMessage(
                    threadId: threadId,
                    role: .system,
                    content: "\(synthesizerName) could not synthesize the plans: \(error.localizedDescription)",
                    participant: "Blink",
                    turnId: turnId
                )
                await persist()
            }
        }

        if !gotAtLeastOneResponse {
            throw ChatProviderError.executionFailed("Planning Session could not get a response from Codex or Claude.")
        }

        return try await finishSecondOpinionTurn(threadId: threadId, turnId: turnId, content: "Synthesis complete.")
    }

    private func finishSecondOpinionTurn(
        threadId: String,
        turnId: String,
        content: String
    ) async throws -> ChatThread {
        let completionMessage = appendMessage(
            threadId: threadId,
            role: .system,
            content: content,
            participant: "Blink",
            turnId: turnId
        )

        guard let latestIndex = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatProviderError.invalidRequest("Chat thread not found.")
        }

        threads[latestIndex].lastError = nil
        threads[latestIndex].updatedAt = completionMessage.createdAt
        await persist()
        return threads[latestIndex]
    }

    private func applyProviderResult(
        provider: ChatProvider,
        result: ChatTurnResult,
        to threadId: String,
        participant: String? = nil,
        turnId: String? = nil,
        layoutHint: ChatMessageLayoutHint? = nil
    ) async throws -> ChatThread {
        let message = appendMessage(
            threadId: threadId,
            role: .assistant,
            content: result.text,
            participant: participant ?? provider.displayName,
            turnId: turnId,
            layoutHint: layoutHint
        )
        attachRuntimeEvents(result.runtimeEvents, to: message)

        guard let index = threads.firstIndex(where: { $0.id == threadId }) else {
            throw ChatProviderError.invalidRequest("Chat thread not found.")
        }

        threads[index].setSessionId(result.sessionId, for: provider)
        threads[index].setBootstrapSummary(nil, for: provider)
        threads[index].lastError = nil
        threads[index].updatedAt = message.createdAt
        await persist()
        return threads[index]
    }

    @discardableResult
    private func appendMessage(
        threadId: String,
        role: ChatMessageRole,
        content: String,
        attachments: [ChatAttachment] = [],
        participant: String? = nil,
        turnId: String? = nil,
        layoutHint: ChatMessageLayoutHint? = nil
    ) -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            threadId: threadId,
            role: role,
            content: content,
            attachments: attachments,
            participant: participant,
            turnId: turnId,
            layoutHint: layoutHint,
            createdAt: Date()
        )
        messagesByThreadId[threadId, default: []].append(message)
        return message
    }

    private func attachRuntimeEvents(_ runtimeEvents: [ChatTurnRuntimeEvent], to message: ChatMessage) {
        guard !runtimeEvents.isEmpty else {
            runtimeEventsByMessageId[message.id] = nil
            return
        }

        let attachedEvents = runtimeEvents.enumerated().map { index, event in
            ChatMessageRuntimeEvent(
                id: event.id.isEmpty ? "\(message.id)-runtime-\(index)" : event.id,
                threadId: message.threadId,
                messageId: message.id,
                kind: event.kind,
                title: event.title,
                detail: event.detail,
                output: event.output,
                status: event.status,
                exitCode: event.exitCode,
                requestId: event.requestId,
                questions: event.questions,
                changedFiles: event.changedFiles,
                createdAt: message.createdAt.addingTimeInterval(Double(index) * 0.001)
            )
        }

        runtimeEventsByMessageId[message.id] = attachedEvents
    }

    private func resolvedModelForSend(
        thread: ChatThread,
        provider: ChatProvider,
        fallbackModel: String
    ) -> String {
        let trimmedThreadModel = thread.model(for: provider)
        return trimmedThreadModel.isEmpty ? fallbackModel : trimmedThreadModel
    }

    private func promptWithAttachmentContext(_ prompt: String, attachments: [ChatAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }

        let attachmentLines = attachments.map { attachment in
            let kind = attachment.isImage ? "image" : "file"
            return "- \(attachment.name) (\(kind)) at \(attachment.path)"
        }

        let attachmentContext = """
        Attached context:
        \(attachmentLines.joined(separator: "\n"))

        Use these workspace files when relevant.
        """

        if prompt.isEmpty {
            return attachmentContext
        }

        return """
        \(prompt)

        \(attachmentContext)
        """
    }

    private func defaultTitle(for provider: ChatProvider) -> String {
        switch provider {
        case .secondOpinion:
            "Planning Session"
        case .codex, .claude:
            "New Chat"
        }
    }

    private func isDefaultTitle(_ title: String) -> Bool {
        title == defaultTitle(for: .codex) || title == defaultTitle(for: .secondOpinion)
    }

    private func bootstrapPromptIfNeeded(
        thread: ChatThread,
        provider: ChatProvider,
        prompt: String
    ) -> String {
        guard thread.sessionId(for: provider) == nil,
              let summary = thread.bootstrapSummary(for: provider),
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return prompt
        }

        return """
        You are joining an existing Blink project chat that already has context from earlier messages.

        Previous conversation summary:
        \(summary)

        Use that summary as context for the next reply, but prioritize the user's newest request below.

        New user request:
        \(prompt)
        """
    }

    private func buildBootstrapSummary(
        for threadId: String,
        targetProvider: ChatProvider
    ) -> String {
        let relevantMessages = messages(for: threadId)
            .filter { $0.role != .system }
            .suffix(8)

        guard !relevantMessages.isEmpty else { return "" }

        let lines = relevantMessages.compactMap { message -> String? in
            let trimmed = condensedTranscriptText(message.content)
            guard !trimmed.isEmpty else { return nil }

            let speaker: String
            switch message.role {
            case .user:
                speaker = "User"
            case .assistant:
                speaker = message.participant ?? "Assistant"
            case .system:
                speaker = "System"
            }

            return "- \(speaker): \(trimmed)"
        }

        guard !lines.isEmpty else { return "" }

        return """
        This summary was prepared when switching the thread to \(targetProvider.displayName).
        It captures the most recent visible discussion so the new provider can continue coherently.

        \(lines.joined(separator: "\n"))
        """
    }

    private func buildImplementationBootstrapSummary(
        planningThreadId: String,
        project: Project,
        route: PlanningRoute?
    ) -> String {
        let latestUserRequest = messages(for: planningThreadId)
            .last(where: { $0.role == .user })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let codexPlan = latestAssistantMessage(in: planningThreadId, participant: "Codex")
        let claudePlan = latestAssistantMessage(in: planningThreadId, participant: "Claude")
        let mergedPlan = latestAssistantMessage(in: planningThreadId, participant: "Merged Plan")

        var sections: [String] = [
            "This chat was started from a Blink Planning Session for project \(project.path)."
        ]

        if !latestUserRequest.isEmpty {
            sections.append("Latest user request:\n\(latestUserRequest)")
        }

        if let route {
            sections.append("Selected planning route: \(route.displayName)")
        }

        switch route {
        case .codex:
            if !codexPlan.isEmpty {
                sections.append("Chosen plan:\n\(codexPlan)")
            }
        case .claude:
            if !claudePlan.isEmpty {
                sections.append("Chosen plan:\n\(claudePlan)")
            }
        case .merged:
            if !mergedPlan.isEmpty {
                sections.append("Merged plan:\n\(mergedPlan)")
            } else {
                if !codexPlan.isEmpty {
                    sections.append("Codex plan:\n\(codexPlan)")
                }
                if !claudePlan.isEmpty {
                    sections.append("Claude plan:\n\(claudePlan)")
                }
            }
        case nil:
            if !codexPlan.isEmpty {
                sections.append("Codex plan:\n\(codexPlan)")
            }
            if !claudePlan.isEmpty {
                sections.append("Claude plan:\n\(claudePlan)")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func buildImplementationStarterPrompt(
        project: Project,
        route: PlanningRoute?
    ) -> String {
        let routeInstruction: String
        switch route {
        case .codex:
            routeInstruction = "Implement the Codex plan for this project."
        case .claude:
            routeInstruction = "Implement the Claude plan for this project."
        case .merged:
            routeInstruction = "Synthesize the Codex and Claude plans into one implementation approach."
        case nil:
            routeInstruction = "Use the planning context above to start implementation."
        }

        return """
        \(routeInstruction)
        Start by restating the implementation approach, then make the first concrete change for \(project.displayPath).
        """
    }

    private func latestAssistantMessage(in threadId: String, participant: String) -> String {
        messages(for: threadId)
            .reversed()
            .first(where: { $0.role == .assistant && $0.participant == participant })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func participantName(for provider: ChatProvider) -> String {
        switch provider {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .secondOpinion:
            "Planning Session"
        }
    }

    private func orderedProviders(for strategy: SecondOpinionStrategy) -> (ChatProvider, ChatProvider) {
        switch strategy {
        case .claudeFirst:
            (.claude, .codex)
        case .codexFirst, .independentFirst:
            (.codex, .claude)
        }
    }

    private func model(
        for provider: ChatProvider,
        codexModel: String,
        claudeModel: String
    ) -> String {
        switch provider {
        case .codex:
            codexModel
        case .claude:
            claudeModel
        case .secondOpinion:
            ""
        }
    }

    private func condensedTranscriptText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.count <= 320 {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 320)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func setActivity(
        for threadId: String,
        title: String,
        detail: String? = nil,
        stepTitles: [String] = [],
        activeStepIndex: Int? = nil
    ) {
        let steps = stepTitles.enumerated().map { index, stepTitle in
            let state: ChatTurnActivityState
            if let activeStepIndex {
                if index < activeStepIndex {
                    state = .completed
                } else if index == activeStepIndex {
                    state = .active
                } else {
                    state = .pending
                }
            } else {
                state = .pending
            }

            return ChatTurnActivityStep(
                id: "\(threadId)-\(index)-\(stepTitle)",
                title: stepTitle,
                state: state
            )
        }

        activityByThreadId[threadId] = ChatTurnActivity(
            title: title,
            detail: detail,
            steps: steps
        )
    }

    private func persist() async {
        let snapshot = ChatStoreSnapshot(
            threads: threads,
            messages: messagesByThreadId.values.flatMap { $0 }.sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.id < right.id
                }
                return left.createdAt < right.createdAt
            },
            runtimeEvents: runtimeEventsByMessageId.values.flatMap { $0 }.sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.id < right.id
                }
                return left.createdAt < right.createdAt
            }
        )

        do {
            try await persistence.save(snapshot)
        } catch {
            // Persistence failures should not crash the UI.
        }
    }

    private static func title(from prompt: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return String(normalized.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendTurn(
        provider: ChatProvider,
        projectPath: String,
        model: String,
        sessionId: String?,
        prompt: String,
        effort: String? = nil,
        permissionLevel: PermissionLevel = .readOnly,
        attachments: [ChatAttachment] = []
    ) async throws -> ChatTurnResult {
        switch provider {
        case .codex:
            try await codexService.sendTurn(
                projectPath: projectPath,
                model: model,
                sessionId: sessionId,
                prompt: prompt,
                effort: effort,
                permissionLevel: permissionLevel,
                attachments: attachments
            )
        case .claude:
            try await claudeService.sendTurn(
                projectPath: projectPath,
                model: model,
                sessionId: sessionId,
                prompt: prompt,
                effort: effort,
                permissionLevel: permissionLevel,
                attachments: attachments
            )
        case .secondOpinion:
            throw ChatProviderError.invalidRequest("Planning Session is an orchestration mode, not a direct CLI provider.")
        }
    }
}
