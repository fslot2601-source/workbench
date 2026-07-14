import SwiftUI
@preconcurrency import Translation

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var filter: SkillListFilter = .all
    @State private var selectedID: String?
    @State private var translations = SkillTranslationCache.load()
    @State private var isTranslating = false
    @State private var translationError: String?

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            skillsContent
                .modifier(
                    SkillTranslationTask(
                        sources: translationSources,
                        translations: $translations,
                        isTranslating: $isTranslating,
                        translationError: $translationError
                    )
                )
        } else {
            skillsContent
        }
    }

    private var skillsContent: some View {
        GeometryReader { geometry in
            let titleBarInset = min(geometry.safeAreaInsets.top, 52)
            let contentHeight = max(0, geometry.size.height - titleBarInset)

            HSplitView {
                VStack(spacing: 0) {
                filterBar
                Divider()
                if let error = model.skillsError, !model.skills.isEmpty {
                    HStack(spacing: 8) {
                        Label("Skills 更新失败，当前仍显示上次成功读取的状态", systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        Button("重试") { Task { await model.refresh(forceReload: true) } }
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.orange.opacity(0.07))
                    .help(error)
                }
                if model.skills.isEmpty && model.isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取 Skills…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.skills.isEmpty, let error = model.skillsError {
                    ContentUnavailableView {
                        Label("Skills 读取失败", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新读取") { Task { await model.refresh(forceReload: true) } }
                    }
                } else if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的 Skill",
                        systemImage: "wand.and.stars.inverse",
                        description: Text("更换筛选条件或重新扫描当前工作区。")
                    )
                } else {
                    List(filteredSkills, selection: $selectedID) { skill in
                        SkillRow(
                            skill: skill,
                            translatedDescription: translatedDescription(for: skill)
                        )
                            .tag(skill.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                .frame(height: contentHeight, alignment: .top)
                .background(WorkbenchTheme.panel)

                Group {
                    if let selectedSkill {
                        SkillDetailView(
                            skill: selectedSkill,
                            translations: translations,
                            isTranslating: isTranslating,
                            translationError: translationError
                        )
                            .id(selectedSkill.id)
                    } else {
                        ContentUnavailableView(
                            "选择一个 Skill",
                            systemImage: "wand.and.stars",
                            description: Text("查看用途、调用方式、来源、依赖和有效状态。")
                        )
                        .frame(minWidth: 360)
                    }
                }
                .frame(height: contentHeight, alignment: .top)
                .background(WorkbenchTheme.canvas)
            }
            .frame(
                width: geometry.size.width,
                height: contentHeight,
                alignment: .topLeading
            )
            .padding(.top, titleBarInset)
        }
        .navigationTitle("Skills")
        .onAppear {
            if selectedID == nil { selectedID = filteredSkills.first?.id }
        }
        .onChange(of: filteredSkills.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索名称、用途或来源", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 9))

            Picker("筛选", selection: $filter) {
                ForEach(SkillListFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
    }

    private var filteredSkills: [SkillRecord] {
        model.skills.filter { skill in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .automatic: skill.invocationPolicy == .automaticAllowed && skill.isEnabled
            case .explicit: skill.invocationPolicy == .explicitOnly && skill.isEnabled
            case .hidden: !skill.isEnabled
            case .attention: skill.hasProblem
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let translatedDescription = translations[skill.description] ?? ""
            let translatedShortDescription = skill.shortDescription.flatMap { translations[$0] } ?? ""
            let haystack = [
                skill.name,
                skill.displayName,
                skill.description,
                skill.shortDescription ?? "",
                translatedDescription,
                translatedShortDescription,
                skill.scope.title
            ]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedSkill: SkillRecord? {
        guard let selectedID else { return nil }
        return model.skills.first { $0.id == selectedID }
    }

    private var translationSources: [String] {
        var seen = Set<String>()
        return model.skills
            .flatMap { skill in
                [skill.description, skill.shortDescription]
                    .compactMap { $0 }
                    + skill.dependencies.compactMap(\.summary)
            }
            .filter { SkillTranslationPolicy.needsChineseTranslation($0) && seen.insert($0).inserted }
    }

    private func translatedDescription(for skill: SkillRecord) -> String? {
        let source = skill.shortDescription ?? skill.description
        guard let translated = translations[source], !translated.isEmpty, translated != source else { return nil }
        return translated
    }
}

private enum SkillListFilter: String, CaseIterable, Identifiable {
    case all, automatic, explicit, hidden, attention
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .automatic: "隐式"
        case .explicit: "显式"
        case .hidden: "隐藏"
        case .attention: "问题"
        }
    }
}

private struct SkillRow: View {
    let skill: SkillRecord
    let translatedDescription: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: skill.effectiveState.symbol)
                .foregroundStyle(skill.effectiveState.color)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(skill.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(translatedDescription ?? skill.shortDescription ?? skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(skill.scope.title)
                    Text("·")
                    Text(skill.mode.title)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                Text(skill.effectiveState.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(skill.effectiveState.color)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

enum SkillTranslationPolicy {
    static func needsChineseTranslation(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinCount = scalars.lazy.filter(isLatinLetter).count
        guard latinCount >= 4 else { return false }
        let hanCount = scalars.lazy.filter(isHanCharacter).count
        guard hanCount > 0 else { return true }

        // Mixed-language descriptions often contain Chinese project names or
        // quoted phrases. Translate when English is still the dominant text,
        // while leaving genuinely Chinese descriptions unchanged.
        return latinCount >= 12 && latinCount >= hanCount * 2
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isHanCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            true
        default:
            false
        }
    }
}

private enum SkillTranslationCache {
    private static let defaultsKey = "skill-description-translations.zh-Hans.v1"

    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    static func save(_ translations: [String: String]) {
        UserDefaults.standard.set(translations, forKey: defaultsKey)
    }
}

@available(macOS 15.0, *)
private struct SkillTranslationTask: ViewModifier {
    let sources: [String]
    @Binding var translations: [String: String]
    @Binding var isTranslating: Bool
    @Binding var translationError: String?

    @State private var configuration: TranslationSession.Configuration?
    @State private var requestedSources: [String] = []

    func body(content: Content) -> some View {
        content
            .task(id: pendingSources) {
                requestTranslation(for: pendingSources)
            }
            .translationTask(configuration) { session in
                await translate(using: session)
            }
    }

    private var pendingSources: [String] {
        sources.filter { translations[$0] == nil }
    }

    @MainActor
    private func requestTranslation(for pending: [String]) {
        guard !pending.isEmpty else {
            isTranslating = false
            return
        }

        requestedSources = pending
        isTranslating = true
        translationError = nil

        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            configuration?.invalidate()
        }
    }

    @MainActor
    private func translate(using session: TranslationSession) async {
        let pending = requestedSources.filter { translations[$0] == nil }
        guard !pending.isEmpty else {
            isTranslating = false
            return
        }

        do {
            var updated = translations
            for source in pending {
                let response = try await session.translate(source)
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { continue }
                updated[source] = translated
            }
            translations = updated
            SkillTranslationCache.save(updated)
            translationError = nil
        } catch is CancellationError {
            return
        } catch {
            translationError = error.localizedDescription
        }
        isTranslating = false
    }
}
