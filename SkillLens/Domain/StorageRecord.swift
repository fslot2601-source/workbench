import Foundation

struct StorageRecord: Identifiable, Hashable, Sendable {
    let kind: CodexStorageKind
    let path: String
    let sizeBytes: Int64
    let itemCount: Int

    var id: String { path }
}

enum CodexStorageKind: String, CaseIterable, Hashable, Sendable {
    case sessions
    case archivedSessions
    case plugins
    case skills
    case packages
    case cache
    case temporary
    case logs
    case database
    case other

    var title: String {
        switch self {
        case .sessions: "会话记录"
        case .archivedSessions: "已归档会话"
        case .plugins: "插件"
        case .skills: "Skills"
        case .packages: "软件包"
        case .cache: "缓存"
        case .temporary: "临时数据"
        case .logs: "诊断日志"
        case .database: "状态数据库"
        case .other: "其他数据"
        }
    }

    var cleanable: Bool {
        switch self {
        case .cache: true
        default: false
        }
    }

    var cleanupImpact: String {
        switch self {
        case .cache: "会删除可重新生成的提供商与网络缓存。"
        case .temporary: "可能包含正在使用的下载与插件同步文件，当前版本只展示、不自动清理。"
        case .logs: "日志可能用于排查问题，当前版本只展示、不自动清理。"
        case .sessions, .archivedSessions: "这是历史会话，不属于缓存，Skill Lens 不提供自动删除。"
        case .plugins, .skills, .packages: "这是已安装能力，不属于缓存，需通过对应管理功能处理。"
        case .database: "这是 Codex 状态数据库，禁止自动清理。"
        case .other: "未知用途的数据保持只读。"
        }
    }
}
