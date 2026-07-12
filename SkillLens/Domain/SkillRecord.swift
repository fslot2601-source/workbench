import Foundation

struct SkillRecord: Identifiable, Hashable, Sendable {
    let name: String
    let displayName: String
    let description: String
    let shortDescription: String?
    let path: String
    let scope: SkillScope
    let rawScope: String
    let isEnabled: Bool
    let invocationPolicy: SkillInvocationPolicy
    let dependencies: [SkillDependency]
    let errors: [String]

    var id: String { path }

    var canModify: Bool { scope == .user || scope == .repo }

    var effectiveState: SkillEffectiveState {
        if !isEnabled { return .disabled }
        if !errors.isEmpty { return .error }
        if dependencies.contains(where: { $0.availability == .missing }) { return .missingDependency }
        return .available
    }

    var hasProblem: Bool {
        isEnabled && [.error, .missingDependency].contains(effectiveState)
    }
}

enum SkillScope: String, CaseIterable, Codable, Sendable {
    case user
    case repo
    case system
    case admin
    case unknown

    init(protocolValue: String) {
        self = SkillScope(rawValue: protocolValue) ?? .unknown
    }

    var title: String {
        switch self {
        case .user: "个人"
        case .repo: "当前项目"
        case .system: "系统内置"
        case .admin: "管理员"
        case .unknown: "未知来源"
        }
    }
}

enum SkillInvocationPolicy: String, CaseIterable, Codable, Sendable {
    case automaticAllowed
    case explicitOnly
    case unknown

    var title: String {
        switch self {
        case .automaticAllowed: "隐式：可自动匹配"
        case .explicitOnly: "显式：仅点名使用"
        case .unknown: "调用方式未知"
        }
    }

    var explanation: String {
        switch self {
        case .automaticAllowed:
            "Codex 可以根据任务描述选择它，也可以通过 $名称 手动点名。"
        case .explicitOnly:
            "Codex 不会根据描述自动选择它，需要在提示词中点名。"
        case .unknown:
            "当前元数据没有给出可靠的调用策略。"
        }
    }
}

enum SkillEffectiveState: String, CaseIterable, Codable, Sendable {
    case available
    case disabled
    case missingDependency
    case error

    var title: String {
        switch self {
        case .available: "可用"
        case .disabled: "隐藏（已停用）"
        case .missingDependency: "缺少依赖"
        case .error: "配置错误"
        }
    }

    var symbol: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .disabled: "pause.circle.fill"
        case .missingDependency: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

struct SkillDependency: Hashable, Sendable {
    let type: String
    let value: String
    let summary: String?
    let availability: DependencyAvailability
}

enum DependencyAvailability: String, Codable, Sendable {
    case available
    case missing
    case unknown
}
