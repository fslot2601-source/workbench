import SwiftUI

struct ConnectionBanner: View {
    let state: CodexConnectionState
    let error: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.callout.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var detail: String? {
        if let error { return error }
        switch state {
        case let .connected(info): return info.userAgent
        case let .connecting(path): return path
        case .locating: return "正在检查常用安装位置。"
        case .idle: return "连接后才能读取有效状态。"
        case let .failed(message): return message
        }
    }

    private var symbol: String {
        if error != nil, case .connected = state { return "exclamationmark.triangle.fill" }
        return switch state {
        case .connected: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .locating, .connecting: "arrow.triangle.2.circlepath"
        case .idle: "circle.dashed"
        }
    }

    private var color: Color {
        if error != nil, case .connected = state { return .orange }
        return switch state {
        case .connected: .green
        case .failed: .red
        case .locating, .connecting: .blue
        case .idle: .secondary
        }
    }
}
