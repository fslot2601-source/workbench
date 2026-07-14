import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summary
                LazyVStack(spacing: 10) {
                    ForEach(model.selfCheckRecords) { record in
                        checkRow(record)
                    }
                }
                systemInformation
            }
            .padding(24)
        }
        .navigationTitle("系统自检")
        .task {
            if !model.hasCompletedInitialRefresh { await model.runSelfCheck() }
        }
        .toolbar {
            Button {
                Task { await model.runSelfCheck() }
            } label: {
                Label("重新自检", systemImage: "arrow.clockwise")
            }
            .disabled(isChecking)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("系统自检").font(.largeTitle.bold())
                Text("检查 Workbench 能否真实读取 Codex；停用、未登录和接口不支持不会被混成故障。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.selfCheckReport, forType: .string)
            } label: {
                Label("复制报告", systemImage: "doc.on.doc")
            }
        }
    }

    private var summary: some View {
        let failures = model.failedSelfCheckCount
        let warnings = model.warningSelfCheckCount
        let color: Color = failures > 0 ? .red : (warnings > 0 ? .orange : .green)
        let title = failures > 0 ? "\(failures) 项需要处理" : (warnings > 0 ? "运行正常，\(warnings) 项需要确认" : "运行正常")
        return HStack(spacing: 14) {
            Image(systemName: failures > 0 ? "xmark.octagon.fill" : (warnings > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                .font(.title)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(isChecking ? "检测仍在进行，结果会自动更新。" : "异常才计入问题；提醒不会影响 Codex 的基本使用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("重新检测") { Task { await model.runSelfCheck() } }
                .disabled(isChecking)
        }
        .padding(16)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func checkRow(_ record: SelfCheckRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: record.status.symbol)
                .foregroundStyle(color(record.status))
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.title).font(.headline)
                    StatusBadge(text: record.status.title, color: color(record.status), symbol: record.status.symbol)
                }
                Text(record.detail).foregroundStyle(.primary)
                Text(record.impact).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if let destination = record.destination, destination != .diagnostics {
                Button("查看") { model.selection = destination }
            } else if record.kind == .connection, record.status == .failed {
                Button("选择 Codex") { model.chooseCodexExecutable() }
            }
        }
        .padding(15)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var systemInformation: some View {
        DisclosureGroup("系统信息") {
            VStack(alignment: .leading, spacing: 8) {
                if case let .connected(info) = model.connectionState {
                    LabeledContent("协议端", value: info.userAgent)
                    LabeledContent("平台", value: "\(info.platformOS) · \(info.platformFamily)")
                    LabeledContent("Codex") { Text(info.executablePath).textSelection(.enabled) }
                    LabeledContent("Codex Home") { Text(info.codexHome).textSelection(.enabled) }
                }
                LabeledContent("工作区") { Text(model.workspaceURL.path).textSelection(.enabled) }
                LabeledContent("Workbench", value: versionText)
            }
            .font(.callout)
            .padding(.top, 10)
        }
        .padding(15)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var isChecking: Bool {
        model.selfCheckRecords.contains { $0.status == .checking }
    }

    private func color(_ status: SelfCheckStatus) -> Color {
        switch status {
        case .passed: .green
        case .notChecked: .secondary
        case .checking: .blue
        case .warning: .orange
        case .failed: .red
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version)（\(build)）"
    }
}
