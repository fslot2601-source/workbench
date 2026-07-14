import SwiftUI

struct BackupView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsUpload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                messages
                githubConnectionCard
                if case .signedIn = model.githubBackupConnection {
                    repositoryCard
                    if selectedRepository != nil {
                        backupHistoryCard
                    }
                }
                scopeCard
                actions
                if let draft = model.backupDraft { preview(draft) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 48)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("Codex 备份")
        .task {
            if case .notChecked = model.githubBackupConnection {
                await model.refreshGitHubBackupState()
            }
        }
        .confirmationDialog("上传备份到 GitHub？", isPresented: $confirmsUpload) {
            Button("上传到私人仓库") { Task { await model.uploadBackup() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("脱敏后的配置快照将上传到 \(model.backupRepository)。Workbench 会在上传前再次确认它是私人仓库。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("配置备份").font(.largeTitle.bold())
            Text("登录 GitHub，选择或新建一个私人仓库，再把脱敏后的 Codex 配置快照备份进去。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.backupError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        if let notice = model.backupNotice {
            HStack {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                if model.backupLastURL != nil {
                    Button("在 GitHub 查看") { model.openLastBackupOnGitHub() }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var githubConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitHub 账号").font(.title2.bold())
                    Text("账号授权由 GitHub 官方工具完成。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionStatus
            }

            Divider()

            switch model.githubBackupConnection {
            case .notChecked, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在检查本机 GitHub 登录状态……")
                        .foregroundStyle(.secondary)
                }
            case .cliMissing:
                VStack(alignment: .leading, spacing: 10) {
                    Text("这台 Mac 还没有安装 GitHub 官方工具，暂时无法登录和上传。")
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://cli.github.com/")!) {
                        Label("查看安装方式", systemImage: "arrow.up.right.square")
                    }
                }
            case .signedOut:
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("尚未登录")
                            .font(.headline)
                        Text("点击后会打开 GitHub 网页完成登录。Workbench 不读取、不显示，也不保存你的 token。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.loginGitHub() }
                    } label: {
                        Label("登录 GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoggingIntoGitHub)
                }
            case .signedIn(let account):
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(account.login)")
                            .font(.headline)
                        Text("登录凭据由 \(account.credentialStorageDescription) 保管")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshGitHubBackupState() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingGitHubBackup)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch model.githubBackupConnection {
        case .notChecked, .checking:
            StatusBadge(text: "检查中", color: .secondary, symbol: "hourglass")
        case .cliMissing:
            StatusBadge(text: "缺少工具", color: .orange, symbol: "exclamationmark.triangle.fill")
        case .signedOut:
            StatusBadge(text: "未登录", color: .secondary, symbol: "person.crop.circle.badge.xmark")
        case .signedIn:
            StatusBadge(text: "已登录", color: .green, symbol: "checkmark.circle.fill")
        }
    }

    private var repositoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("备份仓库").font(.title2.bold())
                Text("这里只显示你账号下已有默认分支的私人仓库。不会把配置传到公开仓库。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.githubBackupRepositories.isEmpty {
                Label("还没有可用的私人仓库，可以在下面直接新建一个。", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                Picker("选择私人仓库", selection: repositorySelection) {
                    Text("请选择").tag("")
                    ForEach(model.githubBackupRepositories) { repository in
                        Text(repository.nameWithOwner).tag(repository.nameWithOwner)
                    }
                }
                .pickerStyle(.menu)

                if let repository = selectedRepository {
                    HStack(spacing: 8) {
                        Label("私人仓库", systemImage: "lock.fill")
                        Text("默认分支：\(repository.defaultBranch)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("新建私人仓库").font(.headline)
                HStack {
                    TextField("skill-lens-backup", text: Binding(
                        get: { model.newBackupRepositoryName },
                        set: { model.newBackupRepositoryName = $0 }
                    ))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await model.createBackupRepository() }
                    } label: {
                        Label("创建", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.newBackupRepositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isCreatingBackupRepository
                    )
                }
                Text("始终创建为私人仓库，并自动建立默认分支；创建前不会上传任何 Codex 内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("备份范围").font(.title2.bold())
            Text("会话、日志、缓存、数据库、auth、插件和 Skills 内容默认不会进入备份。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("AGENTS.md", isOn: optionBinding(\.includeProjectInstructions))
            Toggle("agents 目录", isOn: optionBinding(\.includeAgents))
            Toggle("rules 目录", isOn: optionBinding(\.includeRules))
            Toggle("整理后的 MEMORY.md", isOn: optionBinding(\.includeCuratedMemory))
            Text("Memory 默认不备份；勾选时也只加入整理后的 MEMORY.md，不加入 raw、rollout 或 Chronicle。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var backupHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("备份记录").font(.title2.bold())
                    Text("记录直接来自 GitHub；重装 Workbench 后仍然可以重新读取。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refreshBackupHistory() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingBackupHistory)
            }

            if model.isLoadingBackupHistory && model.backupHistory.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取备份记录……")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            } else if let error = model.backupHistoryError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
            } else if model.backupHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("还没有备份记录")
                        .font(.headline)
                    Text("生成预览并上传后，记录会自动出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.backupHistory) { record in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.headline)
                                Text("已成功写入 \(selectedRepository?.defaultBranch ?? model.backupBranch) · \(record.commitSHA.prefix(8))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                model.openBackupRecord(record)
                            } label: {
                                Label("在 GitHub 查看", systemImage: "arrow.up.right.square")
                            }
                        }
                        .padding(.vertical, 10)
                        if record.id != model.backupHistory.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await model.prepareBackup() }
            } label: {
                Label("生成预览", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingBackup || model.isUploadingBackup)

            Button {
                confirmsUpload = true
            } label: {
                Label("上传备份", systemImage: "arrow.up.circle")
            }
            .disabled(!canUpload)

            if model.isPreparingBackup || model.isUploadingBackup || model.isCreatingBackupRepository {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var selectedRepository: GitHubBackupRepository? {
        model.githubBackupRepositories.first { $0.nameWithOwner == model.backupRepository }
    }

    private var canUpload: Bool {
        guard case .signedIn = model.githubBackupConnection else { return false }
        return model.backupDraft != nil && selectedRepository != nil && !model.isUploadingBackup
    }

    private var repositorySelection: Binding<String> {
        Binding(
            get: { model.backupRepository },
            set: { value in
                guard let repository = model.githubBackupRepositories.first(where: { $0.nameWithOwner == value }) else {
                    model.backupRepository = ""
                    return
                }
                model.selectBackupRepository(repository)
                Task { await model.refreshBackupHistory() }
            }
        )
    }

    private func preview(_ draft: BackupDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("预览").font(.title2.bold())
                Spacer()
                StatusBadge(text: "\(draft.redactionCount) 处脱敏", color: draft.redactionCount > 0 ? .orange : .secondary, symbol: "lock.shield")
            }
            HStack(spacing: 14) {
                MetricCard(title: "文件", value: "\(draft.fileCount)", subtitle: "白名单配置快照", symbol: "doc.on.doc", tint: .blue)
                MetricCard(title: "大小", value: byteText(Int64(draft.byteCount)), subtitle: "上传前打包为单个 JSON", symbol: "shippingbox", tint: .teal)
                MetricCard(title: "排除", value: "\(draft.excludedItems.count)", subtitle: "运行数据和未知数据", symbol: "lock.fill", tint: .purple)
            }
            VStack(spacing: 0) {
                ForEach(draft.includedFiles) { file in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(file.relativePath)
                        Spacer()
                        Text(byteText(Int64(file.content.utf8.count)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if file.id != draft.includedFiles.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(WorkbenchTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
            DisclosureGroup("排除项") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.excludedItems.prefix(80), id: \.self) { item in
                        Text(item).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func optionBinding(_ keyPath: WritableKeyPath<BackupOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.backupOptions[keyPath: keyPath] },
            set: {
                model.backupOptions[keyPath: keyPath] = $0
                model.backupDraft = nil
            }
        )
    }
}

private func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
