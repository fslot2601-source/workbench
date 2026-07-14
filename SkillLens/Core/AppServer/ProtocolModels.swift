import Foundation

struct InitializeResponse: Codable, Sendable {
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOS: String

    private enum CodingKeys: String, CodingKey {
        case userAgent
        case codexHome
        case platformFamily
        case platformOs
        case platformOS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userAgent = try container.decode(String.self, forKey: .userAgent)
        codexHome = try container.decode(String.self, forKey: .codexHome)
        platformFamily = try container.decode(String.self, forKey: .platformFamily)
        platformOS = try container.decodeIfPresent(String.self, forKey: .platformOs)
            ?? container.decode(String.self, forKey: .platformOS)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userAgent, forKey: .userAgent)
        try container.encode(codexHome, forKey: .codexHome)
        try container.encode(platformFamily, forKey: .platformFamily)
        try container.encode(platformOS, forKey: .platformOs)
    }
}

struct SkillsListResponse: Codable, Sendable {
    let data: [SkillsListEntry]
}

struct SkillsListEntry: Codable, Sendable {
    let cwd: String
    let errors: [SkillWireError]
    let skills: [SkillWireMetadata]

    private enum CodingKeys: String, CodingKey { case cwd, errors, skills }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decode(String.self, forKey: .cwd)
        errors = try container.decodeIfPresent([SkillWireError].self, forKey: .errors) ?? []
        skills = try container.decodeIfPresent([SkillWireMetadata].self, forKey: .skills) ?? []
    }
}

struct SkillWireError: Codable, Sendable {
    let message: String
    let path: String
}

struct SkillWireMetadata: Codable, Sendable {
    let name: String
    let description: String
    let shortDescription: String?
    let interface: SkillWireInterface?
    let dependencies: SkillWireDependencies?
    let path: String
    let scope: String
    let enabled: Bool
}

struct SkillWireInterface: Codable, Sendable {
    let displayName: String?
    let shortDescription: String?
    let brandColor: String?
    let defaultPrompt: String?
    let iconSmall: String?
    let iconLarge: String?
}

struct SkillWireDependencies: Codable, Sendable {
    let tools: [SkillWireToolDependency]

    private enum CodingKeys: String, CodingKey { case tools }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tools = try container.decodeIfPresent([SkillWireToolDependency].self, forKey: .tools) ?? []
    }
}

struct SkillWireToolDependency: Codable, Sendable {
    let type: String
    let value: String
    let command: String?
    let description: String?
    let transport: String?
    let url: String?
}

struct HooksListResponse: Codable, Sendable {
    let data: [HooksListEntry]
}

struct HooksListEntry: Codable, Sendable {
    let cwd: String
    let errors: [HookWireError]
    let warnings: [String]
    let hooks: [HookWireMetadata]

    private enum CodingKeys: String, CodingKey { case cwd, errors, warnings, hooks }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decode(String.self, forKey: .cwd)
        errors = try container.decodeIfPresent([HookWireError].self, forKey: .errors) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        hooks = try container.decodeIfPresent([HookWireMetadata].self, forKey: .hooks) ?? []
    }
}

struct HookWireError: Codable, Sendable {
    let message: String
    let path: String
}

struct HookWireMetadata: Codable, Sendable {
    let key: String
    let eventName: String
    let handlerType: String
    let matcher: String?
    let command: String?
    let timeoutSec: Int
    let statusMessage: String?
    let sourcePath: String
    let source: String
    let pluginId: String?
    let displayOrder: Int
    let enabled: Bool
    let isManaged: Bool
    let currentHash: String
    let trustStatus: String

    private enum CodingKeys: String, CodingKey {
        case key, eventName, handlerType, matcher, command, timeoutSec, statusMessage
        case sourcePath, source, pluginId, displayOrder, enabled, isManaged, currentHash, trustStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        eventName = try container.decode(String.self, forKey: .eventName)
        handlerType = try container.decodeIfPresent(String.self, forKey: .handlerType) ?? "unknown"
        matcher = try container.decodeIfPresent(String.self, forKey: .matcher)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        timeoutSec = try container.decodeIfPresent(Int.self, forKey: .timeoutSec) ?? 0
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isManaged = try container.decodeIfPresent(Bool.self, forKey: .isManaged) ?? false
        currentHash = try container.decodeIfPresent(String.self, forKey: .currentHash) ?? ""
        trustStatus = try container.decodeIfPresent(String.self, forKey: .trustStatus) ?? "unknown"
    }
}

struct ConfigReadResponse: Codable, Sendable {
    let config: JSONValue
    let origins: [String: JSONValue]?
    let layers: [ConfigLayerWire]?
}

struct ConfigLayerWire: Codable, Sendable {
    let name: JSONValue
    let version: String
    let config: JSONValue

    var sourceType: String? { name.objectValue?["type"]?.stringValue }
}

struct ConfigBatchWriteResponse: Codable, Sendable {
    let status: String
    let version: String
    let filePath: String
    let overriddenMetadata: JSONValue?
}

struct AccountRateLimitsResponse: Codable, Sendable {
    let rateLimits: RateLimitSnapshotWire
    let rateLimitsByLimitId: [String: RateLimitSnapshotWire]?
    let rateLimitResetCredits: RateLimitResetCreditsWire?
}

struct RateLimitResetCreditsWire: Codable, Sendable {
    let availableCount: Int
}

struct RateLimitSnapshotWire: Codable, Sendable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindowWire?
    let secondary: RateLimitWindowWire?
    let rateLimitReachedType: String?
    let credits: CreditsSnapshotWire?
}

struct RateLimitWindowWire: Codable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?
}

struct CreditsSnapshotWire: Codable, Sendable {
    let balance: String?
    let hasCredits: Bool?
    let unlimited: Bool?
}

struct AccountTokenUsageResponse: Codable, Sendable {
    let summary: AccountTokenUsageSummaryWire
    let dailyUsageBuckets: [DailyTokenUsageWire]?
}

struct AccountTokenUsageSummaryWire: Codable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct DailyTokenUsageWire: Codable, Sendable {
    let startDate: String
    let tokens: Int64
}

struct MCPServerStatusListResponse: Codable, Sendable {
    let data: [MCPServerStatusWire]
    let nextCursor: String?
}

struct MCPServerStatusWire: Codable, Sendable {
    let name: String
    let authStatus: String
    let tools: [String: MCPToolWire]
    let resources: [MCPResourceWire]
    let resourceTemplates: [MCPResourceTemplateWire]
    let serverInfo: MCPServerInfoWire?

    private enum CodingKeys: String, CodingKey {
        case name, authStatus, tools, resources, resourceTemplates, serverInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        authStatus = try container.decodeIfPresent(String.self, forKey: .authStatus) ?? "unknown"
        tools = try container.decodeIfPresent([String: MCPToolWire].self, forKey: .tools) ?? [:]
        resources = try container.decodeIfPresent([MCPResourceWire].self, forKey: .resources) ?? []
        resourceTemplates = try container.decodeIfPresent([MCPResourceTemplateWire].self, forKey: .resourceTemplates) ?? []
        serverInfo = try container.decodeIfPresent(MCPServerInfoWire.self, forKey: .serverInfo)
    }
}

struct MCPToolWire: Codable, Sendable {
    let name: String
    let title: String?
    let description: String?
}

struct MCPResourceWire: Codable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let uri: String
}

struct MCPResourceTemplateWire: Codable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let uriTemplate: String
}

struct MCPServerInfoWire: Codable, Sendable {
    let name: String
    let title: String?
    let version: String?
    let description: String?
    let websiteUrl: String?
}
