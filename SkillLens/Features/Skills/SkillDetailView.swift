import SwiftUI

struct SkillDetailView: View {
    @Environment(AppModel.self) private var model
    let skill: SkillRecord
    @State private var isChanging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                detailSection("它是做什么的") {
                    Text(skill.description)
                        .textSelection(.enabled)
                }
                detailSection("调用方式") {
                    Label(skill.invocationPolicy.title, systemImage: skill.invocationPolicy == .explicitOnly ? "at" : "sparkles")
                        .font(.headline)
                    Text(skill.invocationPolicy.explanation)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("手动点名")
                            .foregroundStyle(.secondary)
                        Text("$\(skill.name)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("这里显示的是 Codex 是否可以发现和选择它，不代表它在某次任务中已经实际运行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                detailSection("来源") {
                    LabeledContent("范围", value: skill.scope.title)
                    if skill.scope == .unknown {
                        LabeledContent("来源原值", value: skill.rawScope)
                    }
                    LabeledContent("标识", value: skill.name)
                    LabeledContent("位置") {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(skill.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                            Button("在 Finder 中显示") { model.revealInFinder(path: skill.path) }
                                .font(.caption)
                        }
                    }
                }
                if !skill.dependencies.isEmpty {
                    detailSection("运行条件") {
                        ForEach(skill.dependencies, id: \.self) { dependency in
                            HStack {
                                Image(systemName: dependencySymbol(dependency.availability))
                                    .foregroundStyle(dependencyColor(dependency.availability))
                                VStack(alignment: .leading) {
                                    Text(dependency.summary ?? dependency.value)
                                    Text("\(dependency.type) · \(dependency.value)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !skill.errors.isEmpty {
                    detailSection("配置问题") {
                        ForEach(skill.errors, id: \.self) { error in
                            Label(error, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(minWidth: 460)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(skill.displayName)
                    .font(.largeTitle.bold())
                HStack {
                    StatusBadge(
                        text: skill.effectiveState.title,
                        color: skill.effectiveState.color,
                        symbol: skill.effectiveState.symbol
                    )
                    StatusBadge(
                        text: skill.invocationPolicy.title,
                        color: skill.invocationPolicy == .explicitOnly ? .indigo : .blue
                    )
                }
            }
            Spacer()
            Button(skill.isEnabled ? "停用" : "启用") {
                isChanging = true
                Task {
                    await model.setSkill(skill, enabled: !skill.isEnabled)
                    isChanging = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(skill.isEnabled ? .secondary : .accentColor)
            .disabled(isChanging || skill.scope == .admin)
            .help(skill.scope == .admin ? "管理员提供的 Skill 不能在这里修改" : "修改后会重新读取并验证 Codex 的实际状态")
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dependencySymbol(_ availability: DependencyAvailability) -> String {
        switch availability {
        case .available: "checkmark.circle.fill"
        case .missing: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func dependencyColor(_ availability: DependencyAvailability) -> Color {
        switch availability {
        case .available: .green
        case .missing: .red
        case .unknown: .secondary
        }
    }
}
