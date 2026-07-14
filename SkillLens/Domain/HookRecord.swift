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

    var configurationStateTitle: String { isEnabled ? "已启用" : "已停用" }

    var displayName: String {
        let normalizedCommand = command?.lowercased() ?? ""
        if normalizedCommand.contains("safety-net") {
            return "Safety Net 安全检查"
        }
        if normalizedCommand.contains("vibe-island-bridge") {
            return "Vibe Island 状态同步"
        }
        if normalizedCommand.contains("subagent-policy-audit") {
            return "子代理配置审计"
        }
        if let pluginID, !pluginID.isEmpty {
            return "\(pluginID) 提供的 Hook"
        }
        if let commandName {
            return commandName
        }
        return "Hook \(shortKey)"
    }

    var shortKey: String {
        let suffix = key
            .split(whereSeparator: { ".:/#".contains($0) })
            .last
            .map(String.init) ?? key
        return suffix.count > 16 ? String(suffix.prefix(16)) + "…" : suffix
    }

    private var commandName: String? {
        guard let command else { return nil }
        let candidates = command.split(whereSeparator: { $0.isWhitespace }).map { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        guard let executable = candidates.last(where: { value in
            value.contains("/") || [".sh", ".py", ".js", ".ts"].contains { value.hasSuffix($0) }
        }) else { return nil }
        let name = URL(fileURLWithPath: executable).deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }

    var triggerSummary: String { event.triggerSummary }

    var matchSummary: String {
        let value = matcher?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matchesEverything = value.isEmpty || value == "*"

        switch event {
        case .preToolUse, .permissionRequest, .postToolUse:
            return matchesEverything
                ? "所有当前支持的终端命令、文件修改和 MCP 调用。"
                : "只匹配工具名称：\(value)"
        case .preCompact, .postCompact:
            return matchesEverything
                ? "手动压缩和自动压缩都会触发。"
                : "只匹配压缩来源：\(value)"
        case .sessionStart:
            return matchesEverything
                ? "新建、恢复、清空，以及压缩后重建上下文都会触发。"
                : "只匹配启动来源：\(value)"
        case .subagentStart, .subagentStop:
            return matchesEverything
                ? "所有子代理类型都会触发。"
                : "只匹配子代理类型：\(value)"
        case .userPromptSubmit, .stop:
            return "每次都会触发；Codex 当前不会为这个事件使用匹配条件。"
        case .unknown:
            return matchesEverything ? "该事件的所有发生情况。" : "匹配条件：\(value)"
        }
    }

    var actionSummary: String {
        if let statusMessage, !statusMessage.isEmpty { return statusMessage }
        let normalizedCommand = command?.lowercased() ?? ""
        if normalizedCommand.contains("vibe-island-bridge") {
            return "同步 Codex 生命周期状态到 Vibe Island。"
        }
        if normalizedCommand.contains("safety-net") {
            return "检查并拦截危险的 Git、删除和命令操作。"
        }
        if normalizedCommand.contains("subagent-policy-audit") {
            return "核对子代理角色与实际模型是否符合配置。"
        }
        switch handlerType {
        case .command: return "运行一个本地命令处理器。"
        case .prompt: return "配置了提示词处理器，但当前 Codex 版本不会执行它。"
        case .agent: return "配置了代理处理器，但当前 Codex 版本不会执行它。"
        case .unknown: return "处理方式无法识别，当前不会确认它能够运行。"
        }
    }

    var effectSummary: String { event.effectSummary }

    var effectTitle: String { event.effectTitle }
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
        case .stop: "本轮即将结束"
        case .unknown: "未知事件"
        }
    }

    var triggerSummary: String {
        switch self {
        case .preToolUse:
            "Codex 准备调用受支持的工具时，在工具真正执行前触发。"
        case .permissionRequest:
            "某个操作需要向你申请额外权限时，在审批提示出现前触发；无需审批的操作不会触发。"
        case .postToolUse:
            "受支持的工具已经返回结果后触发；终端命令执行失败也会触发。"
        case .preCompact:
            "Codex 准备压缩当前对话上下文前触发。"
        case .postCompact:
            "Codex 完成当前对话上下文压缩后触发。"
        case .sessionStart:
            "任务新建、恢复、清空，或压缩后重新建立上下文时触发。"
        case .userPromptSubmit:
            "每次你的提示词即将提交给 Codex 时触发。"
        case .subagentStart:
            "每次一个子代理刚启动时触发。"
        case .subagentStop:
            "每次一个子代理准备结束工作时触发。"
        case .stop:
            "Codex 准备结束当前这一轮回答时触发，不代表整个任务被关闭。"
        case .unknown:
            "当前 Codex 版本没有提供这个事件的已知触发说明。"
        }
    }

    var effectTitle: String {
        switch self {
        case .preToolUse: "可以阻止或改写"
        case .permissionRequest: "可以决定审批"
        case .postToolUse: "只能事后反馈"
        case .preCompact: "可以阻止压缩"
        case .postCompact: "压缩已经完成"
        case .userPromptSubmit: "可以补充或阻止"
        case .subagentStart: "只能提醒"
        case .subagentStop, .stop: "可以要求继续"
        case .sessionStart: "可以补充上下文"
        case .unknown: "影响范围未知"
        }
    }

    var effectSummary: String {
        switch self {
        case .preToolUse:
            "处理器可以允许、改写或拒绝受支持的工具调用，但它不是完整的安全边界。"
        case .permissionRequest:
            "处理器可以允许或拒绝这次审批，也可以不作决定，让 Codex 继续显示正常审批。"
        case .postToolUse:
            "处理器可以反馈问题或改变后续处理，但工具已经运行，不能撤销已经产生的影响。"
        case .preCompact:
            "处理器可以在压缩发生前要求停止。"
        case .postCompact:
            "处理器可以影响压缩后的后续流程，但不能撤销已经完成的压缩。"
        case .sessionStart:
            "处理器可以向新会话补充上下文或显示提醒。"
        case .userPromptSubmit:
            "处理器可以补充上下文，也可以阻止这条提示词继续提交。"
        case .subagentStart:
            "处理器可以向子代理补充上下文或发出警告，但不能阻止子代理启动。"
        case .subagentStop:
            "处理器可以要求子代理继续工作，或接受它结束。"
        case .stop:
            "处理器可以要求 Codex 再继续一轮；这不是关闭整个任务的事件。"
        case .unknown:
            "当前无法确认这个事件能如何影响 Codex 流程。"
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
