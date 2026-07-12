import Foundation

struct AppServerRequest: Encodable, Sendable {
    let method: String
    let id: Int
    let params: JSONValue
}

struct AppServerNotification: Encodable, Sendable {
    let method: String
    let params: JSONValue?
}

struct AppServerIncomingMessage: Decodable, Sendable {
    let id: Int?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: AppServerErrorPayload?
}

struct AppServerErrorPayload: Decodable, Error, Sendable {
    let code: Int
    let message: String
}

struct AppServerEvent: Sendable {
    let method: String
    let params: JSONValue?
}

enum AppServerTransportError: LocalizedError, Sendable {
    case notStarted
    case alreadyStarted
    case processExited
    case invalidResponse
    case timedOut(method: String)
    case malformedMessage(String)
    case requestFailed(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notStarted: "Codex App Server 尚未启动。"
        case .alreadyStarted: "Codex App Server 已经启动。"
        case .processExited: "Codex App Server 已退出。"
        case .invalidResponse: "Codex 返回了无法识别的响应。"
        case let .timedOut(method): "等待 Codex 响应超时：\(method)"
        case let .malformedMessage(message): "Codex 返回了无效消息：\(message)"
        case let .requestFailed(code, message): "Codex 请求失败（\(code)）：\(message)"
        }
    }
}
