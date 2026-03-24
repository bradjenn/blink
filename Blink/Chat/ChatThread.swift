import Foundation

enum SecondOpinionStrategy: String, Codable, CaseIterable, Hashable {
    case independentFirst
    case codexFirst
    case claudeFirst

    var displayName: String {
        switch self {
        case .independentFirst:
            "Independent"
        case .codexFirst:
            "Codex First"
        case .claudeFirst:
            "Claude First"
        }
    }

    var statusText: String {
        switch self {
        case .independentFirst:
            "Both agents answer on their own before either one sees the other."
        case .codexFirst:
            "Codex answers first, then Claude critiques or extends that answer."
        case .claudeFirst:
            "Claude answers first, then Codex critiques or extends that answer."
        }
    }
}

enum PlanningFormat: String, Codable, CaseIterable, Hashable {
    case independent
    case critique
    case debate
    case synthesis

    var displayName: String {
        switch self {
        case .independent:
            "Independent"
        case .critique:
            "Critique"
        case .debate:
            "Debate"
        case .synthesis:
            "Synthesis"
        }
    }
}

enum PlanningRoute: String, Codable, CaseIterable, Hashable {
    case codex
    case claude
    case merged

    var displayName: String {
        switch self {
        case .codex:
            "Use Codex Plan"
        case .claude:
            "Use Claude Plan"
        case .merged:
            "Merge Both"
        }
    }

    var shortLabel: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .merged:
            "Merged"
        }
    }
}

struct ChatThread: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let projectId: String
    var title: String
    var provider: ChatProvider
    var planningFormat: PlanningFormat
    var secondOpinionStrategy: SecondOpinionStrategy
    var selectedPlanningRoute: PlanningRoute?
    var model: String
    var providerModels: [String: String]
    var providerSessionIds: [String: String]
    var providerBootstrapSummaries: [String: String]
    var lastError: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        projectId: String,
        title: String,
        provider: ChatProvider = .codex,
        planningFormat: PlanningFormat = .independent,
        secondOpinionStrategy: SecondOpinionStrategy = .independentFirst,
        selectedPlanningRoute: PlanningRoute? = nil,
        model: String,
        providerModels: [String: String] = [:],
        providerSessionIds: [String: String] = [:],
        providerBootstrapSummaries: [String: String] = [:],
        lastError: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.provider = provider
        self.planningFormat = planningFormat
        self.secondOpinionStrategy = secondOpinionStrategy
        self.selectedPlanningRoute = selectedPlanningRoute
        self.model = model
        self.providerModels = providerModels
        self.providerSessionIds = providerSessionIds
        self.providerBootstrapSummaries = providerBootstrapSummaries
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectId
        case title
        case provider
        case planningFormat
        case secondOpinionStrategy
        case selectedPlanningRoute
        case model
        case providerModels
        case providerSessionIds
        case providerBootstrapSummaries
        case providerSessionId
        case lastError
        case createdAt
        case updatedAt
        case lastResponseId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectId = try container.decode(String.self, forKey: .projectId)
        title = try container.decode(String.self, forKey: .title)
        provider = ChatProvider(
            rawValue: try container.decodeIfPresent(String.self, forKey: .provider) ?? ChatProvider.codex.rawValue
        ) ?? .codex
        let decodedLegacyStrategy =
            try container.decodeIfPresent(SecondOpinionStrategy.self, forKey: .secondOpinionStrategy)
            ?? (provider == .secondOpinion ? .codexFirst : .independentFirst)
        planningFormat =
            try container.decodeIfPresent(PlanningFormat.self, forKey: .planningFormat)
            ?? Self.legacyPlanningFormat(for: decodedLegacyStrategy)
        secondOpinionStrategy = decodedLegacyStrategy
        selectedPlanningRoute = try container.decodeIfPresent(PlanningRoute.self, forKey: .selectedPlanningRoute)
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        providerModels =
            try container.decodeIfPresent([String: String].self, forKey: .providerModels)
            ?? [:]
        if providerModels.isEmpty, !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let legacyProvider = provider == .secondOpinion ? ChatProvider.codex : provider
            providerModels[legacyProvider.rawValue] = legacyModel
        }
        model = Self.legacyModelValue(for: provider, providerModels: providerModels)
        providerSessionIds =
            try container.decodeIfPresent([String: String].self, forKey: .providerSessionIds)
            ?? [:]
        providerBootstrapSummaries =
            try container.decodeIfPresent([String: String].self, forKey: .providerBootstrapSummaries)
            ?? [:]
        let legacySessionId =
            try container.decodeIfPresent(String.self, forKey: .providerSessionId)
            ?? container.decodeIfPresent(String.self, forKey: .lastResponseId)
        if let legacySessionId, providerSessionIds[provider.rawValue] == nil {
            providerSessionIds[provider.rawValue] = legacySessionId
        }
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(title, forKey: .title)
        try container.encode(provider.rawValue, forKey: .provider)
        try container.encode(planningFormat, forKey: .planningFormat)
        try container.encode(secondOpinionStrategy, forKey: .secondOpinionStrategy)
        try container.encodeIfPresent(selectedPlanningRoute, forKey: .selectedPlanningRoute)
        try container.encode(Self.legacyModelValue(for: provider, providerModels: providerModels), forKey: .model)
        try container.encode(providerModels, forKey: .providerModels)
        try container.encode(providerSessionIds, forKey: .providerSessionIds)
        try container.encode(providerBootstrapSummaries, forKey: .providerBootstrapSummaries)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var providerSessionId: String? {
        get { providerSessionIds[provider.rawValue] }
        set { providerSessionIds[provider.rawValue] = newValue }
    }

    func model(for provider: ChatProvider) -> String {
        providerModels[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    mutating func setModel(_ model: String, for provider: ChatProvider) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            providerModels.removeValue(forKey: provider.rawValue)
        } else {
            providerModels[provider.rawValue] = trimmedModel
        }
        self.model = Self.legacyModelValue(for: self.provider, providerModels: providerModels)
    }

    func sessionId(for provider: ChatProvider) -> String? {
        providerSessionIds[provider.rawValue]
    }

    mutating func setSessionId(_ sessionId: String, for provider: ChatProvider) {
        providerSessionIds[provider.rawValue] = sessionId
    }

    func bootstrapSummary(for provider: ChatProvider) -> String? {
        providerBootstrapSummaries[provider.rawValue]
    }

    mutating func setBootstrapSummary(_ summary: String?, for provider: ChatProvider) {
        providerBootstrapSummaries[provider.rawValue] = summary
    }

    private static func legacyModelValue(for provider: ChatProvider, providerModels: [String: String]) -> String {
        let legacyProvider = provider == .secondOpinion ? ChatProvider.codex : provider
        return providerModels[legacyProvider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func legacyPlanningFormat(for strategy: SecondOpinionStrategy) -> PlanningFormat {
        switch strategy {
        case .independentFirst:
            .independent
        case .codexFirst, .claudeFirst:
            .critique
        }
    }
}
