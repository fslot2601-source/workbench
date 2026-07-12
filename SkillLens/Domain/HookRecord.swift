import Foundation

struct HookRecord: Identifiable, Hashable, Sendable {
    let key: String
    let event: HookEvent
    let rawEventName: String
    let handlerType: HookHandlerType
    let rawHandlerType: String
    let matcher: String?
    let command: String?
    let timeoutSeconds: Int
    let statusMessage: String?
    let sourcePath: String
    let source: HookSource
    let rawSource: String
    let pluginID: String?
    let displayOrder: Int
    let isEnabled: Bool
    let isManaged: Bool
    let currentHash: String
    let trustStatus: HookTrustStatus
    let rawTrustStatus: String

    var id: String { "\(sourcePath)#\(key)" }

    var isEffectivelyManaged: Bool {
        isManaged || trustStatus == .managed || [
            HookSource.mdm,
            .cloudManagedConfig,
            .cloudRequirements,
            .legacyManagedConfigFile,
            .legacyManagedConfigMdm
        ].contains(source)
    }

    var runnableState: HookRunnableState {
        if !isEnabled { return .disabled }
        if handlerType != .command { return .unsupportedHandler }
        if isEffectivelyManaged || trustStatus == .trusted { return .ready }
        if trustStatus == .modified { return .changedSinceTrust }
        return .needsTrust
    }
}

enum HookEvent: String, CaseIterable, Codable, Sendable {
    case preToolUse
    case permissionRequest
    case postToolUse
    case preCompact
    case postCompact
    case sessionStart
    case userPromptSubmit
    case subagentStart
    case subagentStop
    case stop
    case unknown

    init(protocolValue: String) {
        let canonical = protocolValue
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch canonical {
        case "pretooluse": self = .preToolUse
        case "permissionrequest": self = .permissionRequest
        case "posttooluse": self = .postToolUse
        case "precompact": self = .preCompact
        case "postcompact": self = .postCompact
        case "sessionstart": self = .sessionStart
        case "userpromptsubmit": self = .userPromptSubmit
        case "subagentstart": self = .subagentStart
        case "subagentstop": self = .subagentStop
        case "stop": self = .stop
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .preToolUse: "操作前检查"
        case .permissionRequest: "审批前判断"
        case .postToolUse: "操作后复核"
        case .preCompact: "压缩上下文前"
        case .postCompact: "压缩上下文后"
        case .sessionStart: "会话开始"
        case .userPromptSubmit: "提交提示词"
        case .subagentStart: "子代理启动"
        case .subagentStop: "子代理结束"
        case .stop: "任务结束"
        case .unknown: "未知事件"
        }
    }
}

enum HookHandlerType: String, Codable, Sendable {
    case command
    case prompt
    case agent
    case unknown

    init(protocolValue: String) {
        self = HookHandlerType(rawValue: protocolValue) ?? .unknown
    }

    var title: String {
        switch self {
        case .command: "本地命令"
        case .prompt: "提示词处理器"
        case .agent: "代理处理器"
        case .unknown: "未知处理器"
        }
    }
}

enum HookTrustStatus: String, Codable, Sendable {
    case managed
    case untrusted
    case trusted
    case modified
    case unknown

    init(protocolValue: String) {
        self = HookTrustStatus(rawValue: protocolValue) ?? .unknown
    }

    var title: String {
        switch self {
        case .managed: "管理员托管"
        case .untrusted: "待信任"
        case .trusted: "已信任"
        case .modified: "信任后已修改"
        case .unknown: "信任状态未知"
        }
    }
}

enum HookSource: String, Codable, Sendable {
    case system, user, project, mdm, sessionFlags, plugin
    case cloudRequirements, cloudManagedConfig
    case legacyManagedConfigFile, legacyManagedConfigMdm
    case unknown

    init(protocolValue: String) {
        self = HookSource(rawValue: protocolValue) ?? .unknown
    }

    var title: String {
        switch self {
        case .system: "系统"
        case .user: "个人"
        case .project: "当前项目"
        case .mdm: "设备管理"
        case .sessionFlags: "本次会话"
        case .plugin: "插件"
        case .cloudRequirements, .cloudManagedConfig: "云端策略"
        case .legacyManagedConfigFile, .legacyManagedConfigMdm: "旧版托管配置"
        case .unknown: "未知来源"
        }
    }
}

enum HookRunnableState: String, Codable, Sendable {
    case ready
    case disabled
    case needsTrust
    case changedSinceTrust
    case unsupportedHandler

    var title: String {
        switch self {
        case .ready: "可以运行"
        case .disabled: "已停用"
        case .needsTrust: "等待信任"
        case .changedSinceTrust: "需要重新信任"
        case .unsupportedHandler: "当前版本不会运行"
        }
    }
}
