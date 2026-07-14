import Foundation

struct MCPListResult: Sendable {
    let servers: [MCPRecord]
    let statusWarning: String?
    let checkedAt: Date
}

enum MCPConversationTestMode: String, CaseIterable, Identifiable, Sendable {
    case visibility
    case realInvocation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibility: "检查是否可见"
        case .realInvocation: "准备真实调用"
        }
    }

    var explanation: String {
        switch self {
        case .visibility:
            "只让 Codex 确认这个 MCP 和工具清单是否出现在新对话中，不调用工具。"
        case .realInvocation:
            "先让 Codex 说明即将执行的操作与风险；只有你在对话中再次确认后才允许调用。"
        }
    }
}

enum MCPConversationTestDraft {
    static func prompt(
        server: MCPRecord,
        mode: MCPConversationTestMode,
        toolName: String? = nil,
        objective: String? = nil
    ) -> String? {
        switch mode {
        case .visibility:
            return """
            这是由 Workbench 创建的 MCP 可用性检查。

            请检查 MCP「\(server.name)」在当前 Codex 对话中是否可见，并用中文回答：
            1. 这个 MCP 是否已经加载；
            2. 当前能看到哪些工具或资源；
            3. 如果不可见，最可能卡在配置、启用、认证、连接还是工具暴露哪一层。

            只检查当前对话可发现的能力，不要调用任何 MCP 工具，不要读取外部数据，不要修改文件或配置。
            """
        case .realInvocation:
            guard let toolName = normalized(toolName),
                  server.tools.contains(where: { $0.name == toolName }),
                  let objective = normalized(objective)
            else { return nil }
            return """
            这是我通过 Workbench 主动发起的 MCP 真实调用测试。

            目标 MCP：\(server.name)
            目标工具：\(toolName)
            我想验证的事情：\(objective)

            第一步只做说明：请先用中文复述你准备怎样调用、会读取或发送什么数据、可能产生什么副作用，并等待我明确回复“确认调用”。在我确认之前，不要调用任何工具，不要读取外部数据，也不要修改任何内容。
            """
        }
    }

    static func codexURL(prompt: String, workspaceURL: URL) -> URL? {
        guard workspaceURL.isFileURL,
              workspaceURL.path.hasPrefix("/"),
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "path", value: workspaceURL.standardizedFileURL.path)
        ]
        return components.url
    }

    private static func normalized(_ value: String?) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else {
            return nil
        }
        return result
    }
}

struct MCPRecord: Identifiable, Hashable, Sendable {
    let name: String
    let displayName: String
    let version: String?
    let description: String?
    let transport: MCPTransport
    let endpointSummary: String
    let isConfigured: Bool
    let isEnabled: Bool
    let isRequired: Bool
    let authStatus: MCPAuthStatus
    let startupStatus: MCPStartupStatus
    let inventoryStatus: MCPInventoryStatus
    let tools: [MCPToolRecord]
    let resources: [MCPResourceRecord]
    let startupTimeoutSeconds: Int?
    let toolTimeoutSeconds: Int?
    let configurationIssue: String?
    let errorMessage: String?
    let checkedAt: Date
    let workspacePath: String
    let canModify: Bool
    let readOnlyReason: String?
    var pendingEnabledState: Bool? = nil

    var id: String { name }
    var toolCount: Int { tools.count }
    var resourceCount: Int { resources.filter { $0.kind == .resource }.count }
    var resourceTemplateCount: Int { resources.filter { $0.kind == .template }.count }
    var capabilityCount: Int { toolCount + resourceCount + resourceTemplateCount }
    var configuredEnabledState: Bool { pendingEnabledState ?? isEnabled }
    var isReloadPending: Bool { pendingEnabledState != nil }

    var effectiveState: MCPEffectiveState {
        guard isEnabled else { return .disabled }
        if configurationIssue != nil { return .configurationProblem }
        if authStatus == .notLoggedIn { return .needsLogin }
        switch startupStatus {
        case .failed, .cancelled: return .startupFailed
        case .starting: return .starting
        default: break
        }
        switch inventoryStatus {
        case .available:
            return capabilityCount > 0 ? .effective : .connectedNoCapabilities
        case .unavailable:
            return .statusUnavailable
        case .notReported:
            return .configuredOnly
        }
    }

    var hasProblem: Bool {
        switch effectiveState {
        case .configurationProblem, .needsLogin, .startupFailed, .connectedNoCapabilities:
            true
        case .effective, .starting, .statusUnavailable, .configuredOnly, .disabled:
            false
        }
    }

    var purposeSummary: String {
        if let description, !description.isEmpty { return description }
        if let tool = tools.first {
            let lead = tool.title ?? tool.name
            return toolCount == 1
                ? "提供“\(lead)”工具。"
                : "提供“\(lead)”等 \(toolCount) 个工具。"
        }
        if !resources.isEmpty { return "提供 \(resources.count) 个可读取资源或资源模板。" }
        return isEnabled ? "Codex 尚未返回这个 MCP 的用途和能力清单。" : "这个 MCP 当前已停用，启用并检测后才能读取用途和能力。"
    }

    var healthChecks: [MCPHealthCheck] {
        [configurationCheck, enabledCheck, authenticationCheck, connectionCheck, capabilityCheck, invocationCheck]
    }

    func updating(startupStatus: MCPStartupStatus, errorMessage: String?) -> MCPRecord {
        MCPRecord(
            name: name,
            displayName: displayName,
            version: version,
            description: description,
            transport: transport,
            endpointSummary: endpointSummary,
            isConfigured: isConfigured,
            isEnabled: isEnabled,
            isRequired: isRequired,
            authStatus: authStatus,
            startupStatus: startupStatus,
            inventoryStatus: inventoryStatus,
            tools: tools,
            resources: resources,
            startupTimeoutSeconds: startupTimeoutSeconds,
            toolTimeoutSeconds: toolTimeoutSeconds,
            configurationIssue: configurationIssue,
            errorMessage: errorMessage,
            checkedAt: checkedAt,
            workspacePath: workspacePath,
            canModify: canModify,
            readOnlyReason: readOnlyReason,
            pendingEnabledState: pendingEnabledState
        )
    }

    func updating(pendingEnabledState: Bool?) -> MCPRecord {
        var copy = self
        copy.pendingEnabledState = pendingEnabledState
        return copy
    }

    private var configurationCheck: MCPHealthCheck {
        if let pendingEnabledState {
            return .init(
                title: "配置",
                status: .attention,
                detail: "已写入\(pendingEnabledState ? "启用" : "停用")配置；当前运行状态仍保持上次检测结果，等待重新加载全部 MCP。"
            )
        }
        if let configurationIssue {
            return .init(title: "配置", status: .failed, detail: configurationIssue)
        }
        if isConfigured {
            return .init(title: "配置", status: .passed, detail: "已在当前有效配置中找到。")
        }
        return .init(title: "配置", status: .attention, detail: "仅由运行状态发现，当前配置层没有返回对应项目。")
    }

    private var enabledCheck: MCPHealthCheck {
        isEnabled
            ? .init(title: "启用开关", status: .passed, detail: "Codex 配置允许加载它。")
            : .init(title: "启用开关", status: .inactive, detail: "当前已停用，不会由 Codex 加载。")
    }

    private var authenticationCheck: MCPHealthCheck {
        guard isEnabled else { return .init(title: "认证", status: .inactive, detail: "停用状态下不检测认证。") }
        return switch authStatus {
        case .notLoggedIn: .init(title: "认证", status: .failed, detail: "需要先完成登录或授权。")
        case .bearerToken, .oAuth: .init(title: "认证", status: .passed, detail: authStatus.title)
        case .unsupported: .init(title: "认证", status: .passed, detail: "服务不要求登录。")
        case .unknown: .init(title: "认证", status: .unknown, detail: "Codex 尚未返回认证状态。")
        }
    }

    private var connectionCheck: MCPHealthCheck {
        guard isEnabled else { return .init(title: "启动与连接", status: .inactive, detail: "停用状态下不会启动。") }
        switch startupStatus {
        case .starting: return .init(title: "启动与连接", status: .attention, detail: "Codex 正在启动或连接。")
        case .ready: return .init(title: "启动与连接", status: .passed, detail: "Codex 已报告连接就绪。")
        case .failed: return .init(title: "启动与连接", status: .failed, detail: errorMessage ?? "Codex 报告启动失败。")
        case .cancelled: return .init(title: "启动与连接", status: .failed, detail: errorMessage ?? "启动或连接已取消。")
        case .inventoryAvailable: return .init(title: "启动与连接", status: .passed, detail: "已从服务读取能力清单。")
        case .configured, .unknown:
            if case .available = inventoryStatus {
                return .init(title: "启动与连接", status: .passed, detail: "已从服务读取能力清单。")
            }
            return .init(title: "启动与连接", status: .unknown, detail: "尚未收到明确的连接结果。")
        case .disabled: return .init(title: "启动与连接", status: .inactive, detail: "当前已停用。")
        }
    }

    private var capabilityCheck: MCPHealthCheck {
        guard isEnabled else { return .init(title: "工具与资源", status: .inactive, detail: "启用后才能读取能力。") }
        switch inventoryStatus {
        case .available:
            return capabilityCount > 0
                ? .init(title: "工具与资源", status: .passed, detail: "已暴露 \(toolCount) 个工具、\(resourceCount + resourceTemplateCount) 个资源。")
                : .init(title: "工具与资源", status: .failed, detail: "连接有响应，但没有暴露任何工具或资源。")
        case let .unavailable(message):
            return .init(title: "工具与资源", status: .unknown, detail: message)
        case .notReported:
            return .init(title: "工具与资源", status: .unknown, detail: "尚未读取到能力清单。")
        }
    }

    private var invocationCheck: MCPHealthCheck {
        .init(
            title: "真实调用",
            status: .notVerified,
            detail: "未自动调用工具，避免读取数据、发送内容或触发其他副作用。"
        )
    }
}

struct MCPToolRecord: Identifiable, Hashable, Sendable {
    let name: String
    let title: String?
    let description: String?
    var id: String { name }
    var displayName: String { title ?? name }
}

struct MCPResourceRecord: Identifiable, Hashable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let kind: MCPResourceKind
    var id: String { "\(kind.rawValue):\(name)" }
    var displayName: String { title ?? name }
}

enum MCPResourceKind: String, Hashable, Sendable {
    case resource, template
    var title: String { self == .resource ? "资源" : "资源模板" }
}

enum MCPInventoryStatus: Hashable, Sendable {
    case available
    case unavailable(String)
    case notReported
}

enum MCPEffectiveState: String, Hashable, Sendable {
    case effective
    case connectedNoCapabilities
    case starting
    case needsLogin
    case configurationProblem
    case startupFailed
    case statusUnavailable
    case configuredOnly
    case disabled

    var title: String {
        switch self {
        case .effective: "已生效"
        case .connectedNoCapabilities: "已连接但无能力"
        case .starting: "正在启动"
        case .needsLogin: "需要登录"
        case .configurationProblem: "配置异常"
        case .startupFailed: "启动失败"
        case .statusUnavailable: "状态检测失败"
        case .configuredOnly: "仅配置，未确认生效"
        case .disabled: "已停用"
        }
    }
}

struct MCPHealthCheck: Identifiable, Hashable, Sendable {
    let title: String
    let status: MCPHealthCheckStatus
    let detail: String
    var id: String { title }
}

enum MCPHealthCheckStatus: String, Hashable, Sendable {
    case passed, attention, failed, inactive, unknown, notVerified

    var title: String {
        switch self {
        case .passed: "通过"
        case .attention: "检测中"
        case .failed: "有问题"
        case .inactive: "未启用"
        case .unknown: "未确认"
        case .notVerified: "未验证"
        }
    }
}

enum MCPTransport: String, Hashable, Sendable {
    case stdio, http, unknown

    var title: String {
        switch self {
        case .stdio: "本地进程"
        case .http: "远程 HTTP"
        case .unknown: "来源未知"
        }
    }
}

enum MCPAuthStatus: String, Hashable, Sendable {
    case unsupported
    case notLoggedIn
    case bearerToken
    case oAuth
    case unknown

    init(protocolValue: String?) {
        switch protocolValue?.replacingOccurrences(of: "_", with: "").lowercased() {
        case "unsupported": self = .unsupported
        case "notloggedin": self = .notLoggedIn
        case "bearertoken": self = .bearerToken
        case "oauth": self = .oAuth
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .unsupported: "不需要登录"
        case .notLoggedIn: "需要登录"
        case .bearerToken: "Bearer 认证"
        case .oAuth: "OAuth 已连接"
        case .unknown: "认证状态未知"
        }
    }
}

enum MCPStartupStatus: String, Hashable, Sendable {
    case unknown
    case configured
    case inventoryAvailable
    case starting
    case ready
    case failed
    case cancelled
    case disabled

    var title: String {
        switch self {
        case .unknown: "运行状态未知"
        case .configured: "已配置"
        case .inventoryAvailable: "能力已读取"
        case .starting: "正在启动"
        case .ready: "已连接"
        case .failed: "启动失败"
        case .cancelled: "已取消"
        case .disabled: "已停用"
        }
    }
}
