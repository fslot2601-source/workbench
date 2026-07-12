import SwiftUI

struct HookActivityView: View {
    let runs: [HookRunRecord]

    var body: some View {
        if runs.isEmpty {
            ContentUnavailableView(
                "还没有可观察的 Hook 运行",
                systemImage: "waveform.path.ecg",
                description: Text("这里只显示 Skill Lens 当前 App Server 连接观察到的瞬态事件；无法确认归属时会标为“已附加会话”。")
            )
        } else {
            VStack(spacing: 0) {
                Text("运行条目会做常见凭据脱敏，但本地 Hook 可输出任意文本；分享截图或日志前仍应人工检查。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.06))
                List(runs) { run in
                    VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(run.event.title, systemImage: statusSymbol(run.status))
                            .font(.headline)
                        Spacer()
                        StatusBadge(text: run.sessionOwnership.title, color: .blue)
                    }
                    HStack(spacing: 12) {
                        Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                        Text(statusTitle(run.status))
                        if let duration = run.durationMilliseconds {
                            Text("\(duration) ms")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(run.entries, id: \.self) { entry in
                        Text("\(DiagnosticRedactor.sanitize(entry.kind))：\(DiagnosticRedactor.commandSummary(entry.text))")
                            .font(.caption)
                            .foregroundStyle(entry.kind == "error" ? .red : .secondary)
                    }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }

    private func statusSymbol(_ status: HookRunStatus) -> String {
        switch status {
        case .running: "hourglass"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .blocked: "hand.raised.fill"
        case .stopped: "stop.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func statusTitle(_ status: HookRunStatus) -> String {
        switch status {
        case .running: "运行中"
        case .completed: "已完成"
        case .failed: "失败"
        case .blocked: "已阻止"
        case .stopped: "已停止"
        case .unknown: "状态未知"
        }
    }
}
