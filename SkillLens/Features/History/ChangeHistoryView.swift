import SwiftUI

struct ChangeHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if model.changeHistory.isEmpty {
                ContentUnavailableView(
                    "还没有变更记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("切换 Skill 状态或启停 Hook 后，写入结果和回读验证会记录在这里。")
                )
            } else {
                List(model.changeHistory) { record in
                    ChangeHistoryRow(record: record)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("变更记录")
        .toolbar {
            if !model.changeHistory.isEmpty {
                Button("清空记录", role: .destructive) {
                    confirmsClear = true
                }
            }
        }
        .confirmationDialog("清空所有本地变更记录？", isPresented: $confirmsClear) {
            Button("清空", role: .destructive) { model.clearChangeHistory() }
        } message: {
            Text("这不会修改 Codex 配置，但清空后无法恢复这些审计记录。")
        }
    }
}

private struct ChangeHistoryRow: View {
    let record: ChangeRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.outcome == .verified ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(record.outcome == .verified ? .green : .red)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.targetName).font(.headline)
                    Text(record.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(changeSummary)
                    .font(.callout)
                Text(record.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(record.occurredAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(record.workspacePath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private var changeSummary: String {
        if let previousState = record.previousState, let requestedState = record.requestedState {
            return "\(previousState) → \(requestedState) · \(record.outcome.title)"
        }
        return "\(record.previousEnabled ? "启用" : "停用") → \(record.requestedEnabled ? "启用" : "停用") · \(record.outcome.title)"
    }
}
