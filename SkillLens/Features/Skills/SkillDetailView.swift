import SwiftUI

struct SkillDetailView: View {
    @Environment(AppModel.self) private var model
    let skill: SkillRecord
    let translations: [String: String]
    let isTranslating: Bool
    let translationError: String?
    @State private var isChanging = false
    @State private var confirmsChange = false
    @State private var pendingMode: SkillMode?
    @State private var showsModeHelp = false
    @State private var showsOriginalDescription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                detailSection("它是做什么的") {
                    Text(displayedDescription)
                        .textSelection(.enabled)
                    translationFooter
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
                                    Text(translatedText(for: dependency.summary) ?? dependency.summary ?? dependency.value)
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
        .frame(minWidth: 360)
        .confirmationDialog(confirmationTitle, isPresented: $confirmsChange) {
            if let pendingMode {
                Button("切换为\(pendingMode.title)", role: pendingMode == .hidden ? .destructive : nil) {
                    isChanging = true
                    Task {
                        await model.setSkill(skill, mode: pendingMode)
                        isChanging = false
                        self.pendingMode = nil
                    }
                }
            }
            Button("取消", role: .cancel) { pendingMode = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var translatedDescription: String? {
        translatedText(for: skill.description)
    }

    private var displayedDescription: String {
        if showsOriginalDescription { return skill.description }
        return translatedDescription ?? skill.description
    }

    @ViewBuilder
    private var translationFooter: some View {
        if translatedDescription != nil {
            HStack(spacing: 8) {
                Label("由 macOS 自动翻译", systemImage: "character.book.closed")
                    .foregroundStyle(.secondary)
                Button(showsOriginalDescription ? "查看中文" : "查看英文原文") {
                    showsOriginalDescription.toggle()
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        } else if SkillTranslationPolicy.needsChineseTranslation(skill.description), isTranslating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在使用 macOS 翻译…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if SkillTranslationPolicy.needsChineseTranslation(skill.description), let translationError {
            Label("自动翻译暂时不可用，当前显示英文原文", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help(translationError)
        }
    }

    private func translatedText(for source: String?) -> String? {
        guard let source else { return nil }
        guard let translated = translations[source], !translated.isEmpty, translated != source else { return nil }
        return translated
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
                        text: skill.mode.title,
                        color: modeColor(skill.mode),
                        symbol: skill.mode.symbol
                    )
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    showsModeHelp.toggle()
                } label: {
                    Label("状态说明", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showsModeHelp, arrowEdge: .top) {
                    modeGuide
                        .padding(18)
                        .frame(width: 380)
                }

                Menu {
                    ForEach(SkillMode.allCases) { mode in
                        Button(role: mode == .hidden ? .destructive : nil) {
                            pendingMode = mode
                            confirmsChange = true
                        } label: {
                            Label(mode.title, systemImage: mode == skill.mode ? "checkmark" : mode.symbol)
                        }
                        .disabled(mode == skill.mode)
                    }
                } label: {
                    Label("切换状态：\(skill.mode.title)", systemImage: skill.mode.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isChanging || model.isChangingConfiguration || !skill.canModify)
                .help(skill.canModify ? "修改后会重新读取并验证 Codex 的实际状态" : "系统、管理员或来源未知的 Skill 不能在这里修改")
            }
        }
    }

    private var confirmationTitle: String {
        guard let pendingMode else { return "切换 Skill 状态？" }
        return "切换为“\(pendingMode.title)”？"
    }

    private var confirmationMessage: String {
        guard let pendingMode else { return "" }
        var message = "\(pendingMode.explanation) 这会修改\(skill.scope == .repo ? "当前项目" : "个人")的 Codex Skill 配置，Workbench 会在写入后重新读取验证。"
        if skill.isPluginProvided, pendingMode != .hidden {
            message += " 这是插件提供的 Skill，更新或重装插件后，调用方式可能恢复为插件默认值。"
        }
        return message
    }

    private var modeGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("三种 Skill 状态")
                .font(.headline)
            ForEach(SkillMode.allCases) { mode in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: mode.symbol)
                        .foregroundStyle(modeColor(mode))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.title)
                            .fontWeight(.semibold)
                        Text(mode.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("“问题”不是第四种状态；它只表示 Skill 配置错误或缺少必要依赖。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func modeColor(_ mode: SkillMode) -> Color {
        switch mode {
        case .implicit: .blue
        case .explicit: .indigo
        case .hidden: .secondary
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
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
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
