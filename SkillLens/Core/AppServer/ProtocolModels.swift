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
}

struct ConfigReadResponse: Codable, Sendable {
    let config: JSONValue
    let origins: [String: JSONValue]
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
