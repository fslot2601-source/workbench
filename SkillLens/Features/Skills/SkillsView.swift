import SwiftUI

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var filter: SkillListFilter = .all
    @State private var selectedID: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                if model.skills.isEmpty && model.isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取 Skills…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的 Skill",
                        systemImage: "wand.and.stars.inverse",
                        description: Text("更换筛选条件或重新扫描当前工作区。")
                    )
                } else {
                    List(filteredSkills, selection: $selectedID) { skill in
                        SkillRow(skill: skill)
                            .tag(skill.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 330, idealWidth: 400)

            if let selectedSkill {
                SkillDetailView(skill: selectedSkill)
                    .id(selectedSkill.id)
            } else {
                ContentUnavailableView(
                    "选择一个 Skill",
                    systemImage: "wand.and.stars",
                    description: Text("查看用途、调用方式、来源、依赖和有效状态。")
                )
                .frame(minWidth: 420)
            }
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
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))

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
            let haystack = [skill.name, skill.displayName, skill.description, skill.shortDescription ?? "", skill.scope.title]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedSkill: SkillRecord? {
        guard let selectedID else { return nil }
        return model.skills.first { $0.id == selectedID }
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
                Text(skill.shortDescription ?? skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(skill.scope.title)
                    Text("·")
                    Text(skill.invocationPolicy.title)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}
