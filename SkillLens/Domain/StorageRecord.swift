import Foundation

struct StorageRecord: Identifiable, Hashable, Sendable {
    let kind: CodexStorageKind
    let path: String
    let sizeBytes: Int64
    let itemCount: Int
    let reclaimableSizeBytes: Int64
    let reclaimableItemCount: Int
    let cleanupFingerprint: String?

    init(
        kind: CodexStorageKind,
        path: String,
        sizeBytes: Int64,
        itemCount: Int,
        reclaimableSizeBytes: Int64 = 0,
        reclaimableItemCount: Int = 0,
        cleanupFingerprint: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.reclaimableSizeBytes = reclaimableSizeBytes
        self.reclaimableItemCount = reclaimableItemCount
        self.cleanupFingerprint = cleanupFingerprint
    }

    var id: String { path }
    var hasReclaimableContent: Bool { reclaimableItemCount > 0 }
}

enum StorageCleanupLevel: String, Hashable, Sendable {
    case safe
    case cautious
    case protected

    var title: String {
        switch self {
        case .safe: "安全清理"
        case .cautious: "谨慎处理"
        case .protected: "只读保护"
        }
    }
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

    var cleanupLevel: StorageCleanupLevel {
        switch self {
        case .cache, .temporary, .logs: .safe
        case .archivedSessions: .cautious
        case .sessions, .plugins, .skills, .packages, .database, .other: .protected
        }
    }

    var cleanable: Bool { cleanupLevel != .protected }

    var cleanupImpact: String {
        switch self {
        case .cache: "删除可重新生成的提供商与网络缓存。"
        case .temporary: "只清理超过 24 小时的临时文件，较新的内容保持不动。"
        case .logs: "只清理超过 7 天的诊断日志，近期日志保留用于排查问题。"
        case .archivedSessions: "这是历史会话；仅在你确认后移到 macOS 废纸篓。"
        case .sessions: "这是当前与历史任务记录，保持只读，避免丢失对话。"
        case .plugins, .skills, .packages: "这是已安装能力，不属于缓存，需通过对应管理功能处理。"
        case .database: "这是 Codex 状态数据库，禁止自动清理。"
        case .other: "未知用途的数据保持只读。"
        }
    }


    var reclaimableDescription: String {
        switch self {
        case .cache: "全部缓存"
        case .temporary: "超过 24 小时"
        case .logs: "超过 7 天"
        case .archivedSessions: "全部归档记录"
        default: "不开放清理"
        }
    }
}
