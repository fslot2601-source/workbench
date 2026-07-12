import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Codex 能力总览")
                        .font(.largeTitle.bold())
                    Text("这里显示当前工作区真正被 Codex 发现的 Skills 和 Hooks。")
                        .foregroundStyle(.secondary)
                }

                ConnectionBanner(state: model.connectionState, error: model.lastError)

                LazyVGrid(columns: columns, spacing: 14) {
                    MetricCard(
                        title: "Skills",
                        value: "\(model.skills.count)",
                        subtitle: "\(availableSkills) 个可用，\(disabledSkills) 个隐藏",
                        symbol: "wand.and.stars",
                        tint: .blue
                    )
                    MetricCard(
                        title: "显式 Skills",
                        value: "\(explicitOnlySkills)",
                        subtitle: "不会根据任务描述自动匹配",
                        symbol: "at",
                        tint: .indigo
                    )
                    MetricCard(
                        title: "Hooks",
                        value: "\(model.hooks.count)",
                        subtitle: "\(runnableHooks) 个可以运行，\(attentionHooks) 个需要处理",
                        symbol: "point.3.connected.trianglepath.dotted",
                        tint: .purple
                    )
                    MetricCard(
                        title: "本连接运行记录",
                        value: "\(model.hookRuns.count)",
                        subtitle: "只统计 Skill Lens 当前连接可观察到的事件",
                        symbol: "clock.arrow.circlepath",
                        tint: .teal
                    )
                }

                Text("状态说明：隐式 Skill 可由 Codex 根据任务自动匹配；显式 Skill 需要用 $名称 点名；隐藏 Skill 不参与发现。这里不把“已启用”误报成“本次已经使用”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))

                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("需要注意")
                            .font(.title2.bold())
                        ForEach(issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
        .navigationTitle("总览")
    }

    private var availableSkills: Int { model.skills.filter { $0.effectiveState == .available }.count }
    private var disabledSkills: Int { model.skills.filter { $0.effectiveState == .disabled }.count }
    private var explicitOnlySkills: Int { model.skills.filter { $0.invocationPolicy == .explicitOnly }.count }
    private var runnableHooks: Int { model.hooks.filter { $0.runnableState == .ready }.count }
    private var attentionHooks: Int { model.hooks.count - runnableHooks }

    private var issues: [String] {
        var values = model.hookWarnings
        let brokenSkills = model.skills.filter { [.error, .missingDependency].contains($0.effectiveState) }.count
        if brokenSkills > 0 { values.append("有 \(brokenSkills) 个 Skill 需要检查配置或依赖。") }
        let trustHooks = model.hooks.filter { [.needsTrust, .changedSinceTrust].contains($0.runnableState) }.count
        if trustHooks > 0 { values.append("有 \(trustHooks) 个 Hook 尚未获得有效信任。") }
        return Array(values.prefix(8))
    }
}
