import Foundation

struct MCPRecord: Identifiable, Hashable, Sendable {
    let name: String
    let displayName: String
    let version: String?
    let description: String?
    let transport: MCPTransport
    let endpointSummary: String
    let isEnabled: Bool
    let isRequired: Bool
    let authStatus: MCPAuthStatus
    let startupStatus: MCPStartupStatus
    let toolCount: Int
    let resourceCount: Int
    let resourceTemplateCount: Int
    let startupTimeoutSeconds: Int?
    let toolTimeoutSeconds: Int?
    let errorMessage: String?

    var id: String { name }

    func updating(startupStatus: MCPStartupStatus, errorMessage: String?) -> MCPRecord {
        MCPRecord(
            name: name,
            displayName: displayName,
            version: version,
            description: description,
            transport: transport,
            endpointSummary: endpointSummary,
            isEnabled: isEnabled,
            isRequired: isRequired,
            authStatus: authStatus,
            startupStatus: startupStatus,
            toolCount: toolCount,
            resourceCount: resourceCount,
            resourceTemplateCount: resourceTemplateCount,
            startupTimeoutSeconds: startupTimeoutSeconds,
            toolTimeoutSeconds: toolTimeoutSeconds,
            errorMessage: errorMessage
        )
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
        self = protocolValue.flatMap(MCPAuthStatus.init(rawValue:)) ?? .unknown
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
