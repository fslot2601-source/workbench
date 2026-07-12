import Foundation

struct HookRunRecord: Identifiable, Hashable, Sendable {
    let id: String
    let threadID: String
    let turnID: String?
    let event: HookEvent
    let rawEventName: String
    let status: HookRunStatus
    let startedAt: Date
    let completedAt: Date?
    let durationMilliseconds: Int?
    let entries: [HookRunEntry]
    let sessionOwnership: SessionOwnership
}
enum HookRunStatus: String, Codable, Sendable {
    case running, completed, failed, blocked, stopped, unknown
}

struct HookRunEntry: Hashable, Sendable {
    let kind: String
    let text: String
}

enum SessionOwnership: String, Codable, Sendable {
    case owned
    case attached
    case configurationOnly

    var title: String {
        switch self {
        case .owned: "本应用会话"
        case .attached: "已附加会话"
        case .configurationOnly: "仅配置状态"
        }
    }
}
