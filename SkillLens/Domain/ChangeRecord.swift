import Foundation

struct ChangeRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let occurredAt: Date
    let kind: ChangeKind
    let targetName: String
    let targetIdentifier: String
    let workspacePath: String
    let previousEnabled: Bool
    let requestedEnabled: Bool
    let outcome: ChangeOutcome
    let message: String

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: ChangeKind,
        targetName: String,
        targetIdentifier: String,
        workspacePath: String,
        previousEnabled: Bool,
        requestedEnabled: Bool,
        outcome: ChangeOutcome,
        message: String
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.targetName = targetName
        self.targetIdentifier = targetIdentifier
        self.workspacePath = workspacePath
        self.previousEnabled = previousEnabled
        self.requestedEnabled = requestedEnabled
        self.outcome = outcome
        self.message = message
    }
}

enum ChangeKind: String, Codable, Sendable {
    case skill
    case hook
    case mcp

    var title: String {
        switch self {
        case .skill: "Skill"
        case .hook: "Hook"
        case .mcp: "MCP"
        }
    }
}

enum ChangeOutcome: String, Codable, Sendable {
    case verified
    case failed

    var title: String { self == .verified ? "已验证" : "未生效" }
}
