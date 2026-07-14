import Foundation

enum SelfCheckKind: String, CaseIterable, Identifiable, Sendable {
    case connection
    case workspace
    case skills
    case hooks
    case memory
    case usage
    case mcp
    case storage
    case backup

    var id: String { rawValue }
}

enum SelfCheckStatus: Int, Comparable, Sendable {
    case passed
    case notChecked
    case checking
    case warning
    case failed

    static func < (lhs: SelfCheckStatus, rhs: SelfCheckStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .passed: "正常"
        case .notChecked: "未检测"
        case .checking: "检测中"
        case .warning: "需确认"
        case .failed: "异常"
        }
    }

    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .notChecked: "minus.circle.fill"
        case .checking: "hourglass.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var isFailure: Bool { self == .failed }
}

struct SelfCheckRecord: Identifiable, Sendable {
    let kind: SelfCheckKind
    let title: String
    let status: SelfCheckStatus
    let detail: String
    let impact: String
    let destination: SidebarDestination?

    var id: SelfCheckKind { kind }
}
