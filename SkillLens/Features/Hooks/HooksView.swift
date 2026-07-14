import SwiftUI

struct HooksView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: HookViewMode = .configuration
    @State private var selectedID: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("显示内容", selection: $mode) {
                ForEach(HookViewMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(12)
            Divider()

            switch mode {
            case .configuration:
                configurationView
            case .activity:
                HookActivityView(runs: model.hookRuns)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Hooks")
        .onAppear {
            if selectedID == nil { selectedID = filteredHooks.first?.id }
        }
        .onChange(of: filteredHooks.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
        }
    }

    private var configurationView: some View {
        GeometryReader { geometry in
            HSplitView {
                VStack(spacing: 0) {
                if !model.hookWarnings.isEmpty {
                    Button {
                        model.selection = .diagnostics
                    } label: {
                        Label("有 \(model.hookWarnings.count) 条 Hook 警告，打开诊断查看", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.orange.opacity(0.07))
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索触发时机、来源或匹配条件", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(9)
                .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 9))
                .padding(12)
                Divider()

                if model.hooks.isEmpty && model.isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取 Hooks…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.hooksError {
                    ContentUnavailableView {
                        Label("Hooks 读取失败", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新读取") { Task { await model.refresh(forceReload: true) } }
                    }
                } else if filteredHooks.isEmpty {
                    ContentUnavailableView(
                        "当前工作区没有 Hook",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Hooks 会按工作区计算有效配置。")
                    )
                } else {
                    List(selection: $selectedID) {
                        ForEach(groupedHooks) { group in
                            Section {
                                ForEach(group.hooks) { hook in
                                    HookRow(hook: hook)
                                        .tag(hook.id)
                                }
                            } header: {
                                HStack {
                                    Text(group.title)
                                    Spacer()
                                    Text("\(group.hooks.count) 个 Hook")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                .frame(height: geometry.size.height)
                .background(WorkbenchTheme.panel)

                Group {
                    if let selectedHook {
                        HookDetailView(hook: selectedHook)
                    } else {
                        ContentUnavailableView("选择一个 Hook", systemImage: "link")
                            .frame(minWidth: 360)
                    }
                }
                .frame(height: geometry.size.height)
                .background(WorkbenchTheme.canvas)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var filteredHooks: [HookRecord] {
        guard !searchText.isEmpty else { return model.hooks }
        return model.hooks.filter { hook in
            [
                hook.event.title,
                hook.displayName,
                hook.key,
                hook.rawEventName,
                hook.source.title,
                hook.matcher ?? "",
                hook.statusMessage ?? "",
                hook.triggerSummary,
                hook.matchSummary,
                hook.actionSummary,
                hook.effectSummary
            ]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedHook: HookRecord? {
        guard let selectedID else { return nil }
        return model.hooks.first { $0.id == selectedID }
    }

    private var groupedHooks: [HookGroup] {
        var groups: [HookGroup] = []
        for hook in filteredHooks {
            if let index = groups.firstIndex(where: { $0.rawEventName == hook.rawEventName }) {
                groups[index].hooks.append(hook)
            } else {
                groups.append(HookGroup(
                    rawEventName: hook.rawEventName,
                    title: hook.event.title,
                    hooks: [hook]
                ))
            }
        }
        return groups
    }
}

private struct HookGroup: Identifiable {
    let rawEventName: String
    let title: String
    var hooks: [HookRecord]
    var id: String { rawEventName }
}
private enum HookViewMode: String, CaseIterable, Identifiable {
    case configuration, activity
    var id: String { rawValue }
    var title: String { self == .configuration ? "配置状态" : "本连接运行记录" }
}

private struct HookRow: View {
    let hook: HookRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hook.runnableState == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(hook.runnableState.color)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(hook.displayName)
                    .font(.headline)
                Text(hook.actionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("匹配：\(hook.matchSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(hook.configurationStateTitle) · \(hook.source.title) · \(hook.runnableState.title)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}
