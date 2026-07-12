import Foundation

enum CodexConnectionState: Equatable, Sendable {
    case idle
    case locating
    case connecting(executablePath: String)
    case connected(CodexServerInfo)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "尚未连接"
        case .locating: "正在查找 Codex"
        case .connecting: "正在连接"
        case .connected: "已连接"
        case .failed: "连接失败"
        }
    }
}
struct CodexServerInfo: Equatable, Sendable {
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOS: String
    let executablePath: String
    let connectionID: UUID
}
