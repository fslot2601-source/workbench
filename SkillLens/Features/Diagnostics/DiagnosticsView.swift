import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("连接") {
                ConnectionBanner(state: model.connectionState, error: model.lastError)
                if case let .connected(info) = model.connectionState {
                    LabeledContent("协议端", value: info.userAgent)
                    LabeledContent("Codex 可执行文件", value: info.executablePath)
                    LabeledContent("Codex Home", value: info.codexHome)
                    LabeledContent("平台", value: "\(info.platformOS) · \(info.platformFamily)")
                }
                Button("手动选择 Codex") {
                    model.chooseCodexExecutable()
                }
            }

            Section("当前工作区") {
                Text(model.workspaceURL.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("切换工作区") {
                    model.chooseWorkspace()
                }
            }

            Section("数据范围") {
                LabeledContent("Skills", value: "\(model.skills.count)")
                LabeledContent("Hooks", value: "\(model.hooks.count)")
                LabeledContent("可观察运行记录", value: "\(model.hookRuns.count)")
                Text("Hook 运行记录只来自本应用连接，不推断其他 Codex Desktop 或 CLI 进程的状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: versionText)
                LabeledContent("最低系统", value: "macOS 14")
                Text("Skill Lens 是独立开源项目，不包含遥测、广告或独立账户系统。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.hookWarnings.isEmpty {
                Section("Hook 警告") {
                    ForEach(model.hookWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("诊断")
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version)（\(build)）"
    }
}
