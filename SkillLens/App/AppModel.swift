import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selection: SidebarDestination = .dashboard
    var workspaceURL: URL
    var connectionState: CodexConnectionState = .idle
    var skills: [SkillRecord] = []
    var hooks: [HookRecord] = []
    var hookWarnings: [String] = []
    var skillsError: String?
    var hooksError: String?
    var hookRuns: [HookRunRecord] = []
    var rateLimits: [RateLimitRecord] = []
    var resetCreditsAvailable: Int?
    var tokenUsageSummary: TokenUsageSummary?
    var dailyTokenUsage: [DailyTokenUsage] = []
    var usageRefreshedAt: Date?
    var usageError: String?
    var mcpServers: [MCPRecord] = []
    var mcpError: String?
    var mcpWarning: String?
    var storageRecords: [StorageRecord] = []
    var storageError: String?
    var storageNotice: String?
    var memorySnapshot: MemorySnapshot?
    var memoryError: String?
    var backupDraft: BackupDraft?
    var backupError: String?
    var backupNotice: String?
    var backupHistoryError: String?
    var backupRepository = UserDefaults.standard.string(forKey: "backupRepository") ?? ""
    var backupBranch = UserDefaults.standard.string(forKey: "backupBranch") ?? "main"
    var backupOptions = BackupOptions()
    var githubBackupConnection: GitHubBackupConnectionState = .notChecked
    var githubBackupRepositories: [GitHubBackupRepository] = []
    var backupHistory: [GitHubBackupHistoryRecord] = []
    var newBackupRepositoryName = "skill-lens-backup"
    var backupLastURL: String?
    var changeHistory: [ChangeRecord] = []
    var isRefreshing = false
    var isRefreshingUsage = false
    var isRefreshingMCP = false
    var isReloadingAllMCP = false
    var isScanningStorage = false
    var isClearingStorage = false
    var isScanningMemory = false
    var isPreparingBackup = false
    var isUploadingBackup = false
    var isRefreshingGitHubBackup = false
    var isLoggingIntoGitHub = false
    var isCreatingBackupRepository = false
    var isLoadingBackupHistory = false
    var isChangingConfiguration = false
    var hasCompletedInitialRefresh = false
    var lastError: String?

    private let service = CodexService()
    private let locator = CodexExecutableLocator()
    private let storageService = CodexStorageService()
    private let memoryService = CodexMemoryService()
    private let backupService = CodexBackupService()
    private var eventTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private var workspaceGeneration = 0
    private var connectionGeneration = 0
    private var activeConnectionID: UUID?
    private var activeRefreshID: UUID?
    private var backupHistoryRequestID: UUID?

    init() {
        if let rawDestination = ProcessInfo.processInfo.environment["SKILLLENS_START_DESTINATION"],
           let destination = SidebarDestination(rawValue: rawDestination) {
            selection = destination
        }
        if let saved = UserDefaults.standard.string(forKey: "workspacePath"), !saved.isEmpty {
            workspaceURL = URL(fileURLWithPath: saved).standardizedFileURL
        } else {
            workspaceURL = FileManager.default.homeDirectoryForCurrentUser
        }
        loadChangeHistory()
    }

    func bootstrap() async {
        if hasBootstrapped {
            if case .failed = connectionState { await refreshOverview(forceReload: true) }
            return
        }
        hasBootstrapped = true
        await refreshOverview(forceReload: true)
    }

    func refreshOverview(forceReload: Bool = false) async {
        await refresh(forceReload: forceReload)
        guard case .connected = connectionState else { return }

        async let usage: Void = refreshUsage()
        async let mcp: Void = refreshMCP()
        async let storage: Void = scanStorage()
        async let memory: Void = scanMemory()
        _ = await (usage, mcp, storage, memory)
    }

    func refresh(forceReload: Bool = false) async {
        let requestID = UUID()
        let generation = workspaceGeneration
        let workspace = workspaceURL
        activeRefreshID = requestID
        isRefreshing = true
        lastError = nil
        skillsError = nil
        hooksError = nil
        defer {
            if activeRefreshID == requestID {
                isRefreshing = false
                hasCompletedInitialRefresh = true
            }
        }

        do {
            _ = try await ensureConnected()

            var partialFailures: [String] = []
            do {
                let result = try await service.listSkills(cwd: workspace, forceReload: forceReload)
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                skills = result
                skillsError = nil
            } catch {
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                skills = []
                let message = safeMessage(error)
                skillsError = message
                partialFailures.append("Skills：\(message)")
            }
            do {
                let hookResult = try await service.listHooks(cwd: workspace)
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                hooks = hookResult.hooks
                hookWarnings = hookResult.warnings
                hooksError = nil
            } catch {
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                hooks = []
                hookWarnings = []
                let message = safeMessage(error)
                hooksError = message
                partialFailures.append("Hooks：\(message)")
            }
            if activeRefreshID == requestID, !partialFailures.isEmpty {
                lastError = "部分功能不可用。" + partialFailures.joined(separator: "；")
            }
        } catch {
            guard activeRefreshID == requestID,
                  workspaceGeneration == generation,
                  workspaceURL == workspace
            else { return }
            let message = safeMessage(error)
            skills = []
            hooks = []
            hookWarnings = []
            skillsError = message
            hooksError = message
            lastError = message
            connectionState = .failed(message)
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择要检查的工作区"
        panel.prompt = "使用此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspaceURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newWorkspace = url.standardizedFileURL
        guard newWorkspace != workspaceURL else { return }
        workspaceGeneration += 1
        workspaceURL = newWorkspace
        skills = []
        hooks = []
        hookWarnings = []
        skillsError = nil
        hooksError = nil
        hookRuns = []
        mcpServers = []
        mcpError = nil
        mcpWarning = nil
        memorySnapshot = nil
        memoryError = nil
        backupDraft = nil
        backupError = nil
        backupNotice = nil
        UserDefaults.standard.set(workspaceURL.path, forKey: "workspacePath")
        Task { await refreshOverview(forceReload: true) }
    }

    func chooseCodexExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 可执行文件"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        connectionGeneration += 1
        UserDefaults.standard.set(url.path, forKey: "codexExecutablePath")
        Task {
            activeConnectionID = nil
            hookRuns = []
            await service.disconnect()
            connectionState = .idle
            await refreshOverview(forceReload: true)
        }
    }

    func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func setSkill(_ skill: SkillRecord, mode: SkillMode) async {
        let workspace = workspaceURL
        let generation = workspaceGeneration
        guard !isChangingConfiguration else {
            lastError = AppModelError.configurationChangeInProgress.localizedDescription
            return
        }
        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        lastError = nil
        guard skill.mode != mode else { return }

        var metadataMutation: SkillMetadataMutation?
        var changedEnabledState = false
        do {
            guard skill.canModify else { throw CodexServiceError.protectedSkill }

            if mode != .hidden {
                let desiredPolicy: SkillInvocationPolicy = mode == .explicit ? .explicitOnly : .automaticAllowed
                if skill.invocationPolicy != desiredPolicy {
                    metadataMutation = try await service.setSkillInvocationPolicy(
                        skill,
                        policy: desiredPolicy,
                        cwd: workspace
                    )
                }
                if !skill.isEnabled {
                    try await service.setSkillEnabled(skill, enabled: true, cwd: workspace)
                    changedEnabledState = true
                }
            } else if skill.isEnabled {
                try await service.setSkillEnabled(skill, enabled: false, cwd: workspace)
                changedEnabledState = true
            }

            let refreshed = try await service.listSkills(cwd: workspace, forceReload: true)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            guard refreshed.first(where: { $0.path == skill.path })?.mode == mode else {
                throw AppModelError.writeVerificationFailed
            }
            skills = refreshed
            addChange(
                kind: .skill,
                name: skill.displayName,
                identifier: skill.path,
                previous: skill.isEnabled,
                requested: mode != .hidden,
                previousState: skill.mode.title,
                requestedState: mode.title,
                outcome: .verified,
                message: "Codex 启停状态与 Skill 调用策略已重新读取，确认为“\(mode.title)”。"
            )
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            var rollbackMessages: [String] = []
            if changedEnabledState {
                do {
                    try await service.setSkillEnabled(skill, enabled: skill.isEnabled, cwd: workspace)
                } catch {
                    rollbackMessages.append("启停状态回滚失败：\(safeMessage(error))")
                }
            }
            if let metadataMutation {
                do {
                    try await service.restoreSkillInvocationPolicy(metadataMutation)
                } catch {
                    rollbackMessages.append("调用策略回滚失败：\(safeMessage(error))")
                }
            }
            if changedEnabledState || metadataMutation != nil,
               let restored = try? await service.listSkills(cwd: workspace, forceReload: true) {
                skills = restored
            }
            lastError = safeMessage(error)
            let rollbackSuffix = rollbackMessages.isEmpty
                ? "原状态已回滚。"
                : rollbackMessages.joined(separator: "；")
            addChange(
                kind: .skill,
                name: skill.displayName,
                identifier: skill.path,
                previous: skill.isEnabled,
                requested: mode != .hidden,
                previousState: skill.mode.title,
                requestedState: mode.title,
                outcome: .failed,
                message: "\(safeMessage(error)) \(rollbackSuffix)"
            )
        }
    }

    func setSkill(_ skill: SkillRecord, enabled: Bool) async {
        let enabledMode: SkillMode = skill.invocationPolicy == .explicitOnly ? .explicit : .implicit
        await setSkill(skill, mode: enabled ? enabledMode : .hidden)
    }

    func setHook(_ hook: HookRecord, enabled: Bool) async {
        let workspace = workspaceURL
        let generation = workspaceGeneration
        guard !isChangingConfiguration else {
            lastError = AppModelError.configurationChangeInProgress.localizedDescription
            return
        }
        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        lastError = nil
        do {
            guard !hook.isEffectivelyManaged else { throw CodexServiceError.managedHook }
            try await service.setHookEnabled(hook, enabled: enabled, cwd: workspace)
            let result = try await service.listHooks(cwd: workspace)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            guard result.hooks.first(where: { $0.key == hook.key })?.isEnabled == enabled else {
                throw CodexServiceError.writeVerificationFailed
            }
            hooks = result.hooks
            hookWarnings = result.warnings
            addChange(
                kind: .hook,
                name: hook.displayName,
                identifier: hook.key,
                previous: hook.isEnabled,
                requested: enabled,
                outcome: .verified,
                message: "Codex 配置版本校验通过，并重新读取确认状态生效。"
            )
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            lastError = safeMessage(error)
            addChange(
                kind: .hook,
                name: hook.displayName,
                identifier: hook.key,
                previous: hook.isEnabled,
                requested: enabled,
                outcome: .failed,
                message: safeMessage(error)
            )
        }
    }

    func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        usageError = nil
        defer { isRefreshingUsage = false }
        do {
            _ = try await ensureConnected()
            var failures: [String] = []
            do {
                let result = try await service.readRateLimits()
                rateLimits = result.records
                resetCreditsAvailable = result.resetCredits
            } catch {
                rateLimits = []
                resetCreditsAvailable = nil
                failures.append("限额：\(safeMessage(error))")
            }
            do {
                let result = try await service.readTokenUsage()
                tokenUsageSummary = result.summary
                dailyTokenUsage = result.daily
            } catch {
                tokenUsageSummary = nil
                dailyTokenUsage = []
                failures.append("Token 用量：\(safeMessage(error))")
            }
            usageRefreshedAt = Date()
            if !failures.isEmpty { usageError = failures.joined(separator: "；") }
        } catch {
            rateLimits = []
            resetCreditsAvailable = nil
            tokenUsageSummary = nil
            dailyTokenUsage = []
            usageError = safeMessage(error)
        }
    }

    func refreshMCP(clearPendingReloads: Bool = false) async {
        guard !isRefreshingMCP else { return }
        let workspace = workspaceURL
        let generation = workspaceGeneration
        let previousServers = mcpServers
        let pendingByName = Dictionary(uniqueKeysWithValues: previousServers.compactMap { server in
            server.pendingEnabledState.map { (server.name, $0) }
        })
        isRefreshingMCP = true
        mcpError = nil
        mcpWarning = nil
        defer { isRefreshingMCP = false }
        do {
            _ = try await ensureConnected()
            let configured = try await service.listConfiguredMCPServers(cwd: workspace)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            if previousServers.isEmpty {
                mcpServers = configured.servers.map {
                    $0.updating(pendingEnabledState: clearPendingReloads ? nil : pendingByName[$0.name])
                }
            }
            let result = try await service.listMCPServers(cwd: workspace)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpServers = result.servers.map { freshServer in
                if !clearPendingReloads,
                   let pending = pendingByName[freshServer.name],
                   let previous = previousServers.first(where: { $0.name == freshServer.name }) {
                    return previous.updating(pendingEnabledState: pending)
                }
                return freshServer.updating(pendingEnabledState: nil)
            }
            mcpWarning = result.statusWarning
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            if previousServers.isEmpty { mcpServers = [] }
            mcpError = safeMessage(error)
            mcpWarning = nil
        }
    }

    func setMCP(_ server: MCPRecord, enabled: Bool) async {
        let workspace = workspaceURL
        let generation = workspaceGeneration
        guard server.workspacePath == workspaceURL.path else {
            mcpError = "工作区已经切换。请重新读取 MCP 后再修改。"
            return
        }
        guard server.canModify else {
            mcpError = server.readOnlyReason ?? "这个 MCP 配置保持只读。"
            return
        }
        guard !isChangingConfiguration else {
            mcpError = AppModelError.configurationChangeInProgress.localizedDescription
            return
        }
        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        mcpError = nil
        do {
            try await service.setMCPEnabled(name: server.name, enabled: enabled, cwd: workspace)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            guard let index = mcpServers.firstIndex(where: { $0.name == server.name }) else {
                throw CodexServiceError.writeVerificationFailed
            }
            mcpServers[index] = mcpServers[index].updating(
                pendingEnabledState: enabled == mcpServers[index].isEnabled ? nil : enabled
            )
            addChange(
                kind: .mcp,
                name: server.displayName,
                identifier: server.name,
                previous: server.configuredEnabledState,
                requested: enabled,
                outcome: .verified,
                message: "目标 MCP 配置已通过版本校验并回读验证；运行状态尚未重载，其他 MCP 未受影响。"
            )
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpError = safeMessage(error)
            addChange(
                kind: .mcp,
                name: server.displayName,
                identifier: server.name,
                previous: server.configuredEnabledState,
                requested: enabled,
                outcome: .failed,
                message: safeMessage(error)
            )
        }
    }

    func reloadAllMCP() async {
        guard !isReloadingAllMCP, !isRefreshingMCP, !isChangingConfiguration else { return }
        let workspace = workspaceURL
        let generation = workspaceGeneration
        isReloadingAllMCP = true
        mcpError = nil
        defer { isReloadingAllMCP = false }
        do {
            _ = try await ensureConnected()
            try await service.reloadAllMCPServers()
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            await refreshMCP(clearPendingReloads: true)
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpError = "重新加载全部 MCP 失败：\(safeMessage(error))"
        }
    }

    func scanStorage() async {
        guard !isScanningStorage else { return }
        isScanningStorage = true
        storageError = nil
        storageNotice = nil
        defer { isScanningStorage = false }
        do {
            let info = try await ensureConnected()
            storageRecords = await storageService.scan(codexHome: URL(fileURLWithPath: info.codexHome))
        } catch {
            storageRecords = []
            storageError = safeMessage(error)
        }
    }

    func clearStorage(_ record: StorageRecord) async {
        guard record.kind.cleanable, record.hasReclaimableContent, !isClearingStorage else { return }
        isClearingStorage = true
        storageError = nil
        defer { isClearingStorage = false }
        do {
            let info = try await ensureConnected()
            let home = URL(fileURLWithPath: info.codexHome)
            connectionGeneration += 1
            activeConnectionID = nil
            hookRuns = []
            await service.disconnect()
            connectionState = .idle
            let result = try await storageService.clear(record: record, codexHome: home)
            storageRecords = await storageService.scan(codexHome: home)
            let size = ByteCountFormatter.string(fromByteCount: result.reclaimedBytes, countStyle: .file)
            switch result.disposition {
            case .movedToTrash:
                storageNotice = "已将 \(result.reclaimedItemCount) 个文件（\(size)）移到 macOS 废纸篓，需要时可以恢复。"
            case .permanentlyRemoved:
                storageNotice = "已清理 \(result.reclaimedItemCount) 个可重新生成的文件（\(size)）。受保护数据没有被修改。"
            }
            await refresh(forceReload: true)
        } catch {
            storageError = safeMessage(error)
            if case .connected = connectionState { } else { await refresh(forceReload: false) }
        }
    }

    func scanMemory() async {
        guard !isScanningMemory else { return }
        isScanningMemory = true
        memoryError = nil
        defer { isScanningMemory = false }
        do {
            let info = try await ensureConnected()
            memorySnapshot = await memoryService.scan(codexHome: URL(fileURLWithPath: info.codexHome))
        } catch {
            memorySnapshot = nil
            memoryError = safeMessage(error)
        }
    }

    func prepareBackup() async {
        guard !isPreparingBackup else { return }
        isPreparingBackup = true
        backupError = nil
        backupNotice = nil
        defer { isPreparingBackup = false }
        do {
            let info = try await ensureConnected()
            let userConfig = try await service.readUserConfig(cwd: workspaceURL)
            backupDraft = try await backupService.makeDraft(
                codexHome: URL(fileURLWithPath: info.codexHome),
                userConfig: userConfig,
                options: backupOptions
            )
        } catch {
            backupDraft = nil
            backupError = safeMessage(error)
        }
    }

    func refreshGitHubBackupState() async {
        guard !isRefreshingGitHubBackup else { return }
        isRefreshingGitHubBackup = true
        githubBackupConnection = .checking
        defer { isRefreshingGitHubBackup = false }
        do {
            let status = try await backupService.githubConnectionStatus()
            githubBackupConnection = status
            guard case .signedIn(let account) = status else {
                githubBackupRepositories = []
                backupHistory = []
                backupRepository = ""
                return
            }
            do {
                let repositories = try await backupService.listPrivateRepositories(account: account)
                githubBackupRepositories = repositories
                let selected = repositories.first { $0.nameWithOwner == backupRepository }
                    ?? repositories.first { $0.nameWithOwner.lowercased().hasSuffix("/skill-lens-backup") }
                if let selected {
                    selectBackupRepository(selected)
                } else {
                    backupRepository = ""
                    backupBranch = "main"
                }
            } catch {
                githubBackupRepositories = []
                backupRepository = ""
                backupBranch = "main"
                backupError = safeMessage(error)
            }
            if !backupRepository.isEmpty {
                await refreshBackupHistory()
            }
        } catch BackupError.githubCLIMissing {
            githubBackupConnection = .cliMissing
            githubBackupRepositories = []
            backupHistory = []
            backupRepository = ""
        } catch {
            githubBackupConnection = .signedOut
            githubBackupRepositories = []
            backupHistory = []
            backupRepository = ""
            backupError = safeMessage(error)
        }
    }

    func loginGitHub() async {
        guard !isLoggingIntoGitHub else { return }
        isLoggingIntoGitHub = true
        backupError = nil
        backupNotice = nil
        defer { isLoggingIntoGitHub = false }
        do {
            _ = try await backupService.loginToGitHub()
            backupNotice = "GitHub 登录成功。现在可以选择或新建私人仓库。"
            await refreshGitHubBackupState()
        } catch {
            backupError = safeMessage(error)
            await refreshGitHubBackupState()
        }
    }

    func createBackupRepository() async {
        guard !isCreatingBackupRepository else { return }
        guard case .signedIn(let account) = githubBackupConnection else {
            backupError = "请先登录 GitHub。"
            return
        }
        isCreatingBackupRepository = true
        backupError = nil
        backupNotice = nil
        defer { isCreatingBackupRepository = false }
        do {
            let repository = try await backupService.createPrivateRepository(
                name: newBackupRepositoryName,
                account: account
            )
            githubBackupRepositories = try await backupService.listPrivateRepositories(account: account)
            if let refreshed = githubBackupRepositories.first(where: { $0.nameWithOwner == repository.nameWithOwner }) {
                selectBackupRepository(refreshed)
            } else {
                githubBackupRepositories.insert(repository, at: 0)
                selectBackupRepository(repository)
            }
            backupNotice = "已创建私人仓库 \(repository.nameWithOwner)。"
            await refreshBackupHistory()
        } catch {
            backupError = safeMessage(error)
        }
    }

    func selectBackupRepository(_ repository: GitHubBackupRepository) {
        backupRepository = repository.nameWithOwner
        backupBranch = repository.defaultBranch
        backupHistory = []
        backupHistoryError = nil
        UserDefaults.standard.set(repository.nameWithOwner, forKey: "backupRepository")
        UserDefaults.standard.set(repository.defaultBranch, forKey: "backupBranch")
    }

    func refreshBackupHistory() async {
        guard let repository = githubBackupRepositories.first(where: { $0.nameWithOwner == backupRepository }) else {
            backupHistory = []
            backupHistoryError = nil
            return
        }
        let requestID = UUID()
        backupHistoryRequestID = requestID
        isLoadingBackupHistory = true
        backupHistoryError = nil
        defer {
            if backupHistoryRequestID == requestID {
                isLoadingBackupHistory = false
            }
        }
        do {
            let records = try await backupService.listBackupHistory(repository: repository)
            guard backupHistoryRequestID == requestID,
                  backupRepository == repository.nameWithOwner
            else { return }
            backupHistory = records
        } catch {
            guard backupHistoryRequestID == requestID,
                  backupRepository == repository.nameWithOwner
            else { return }
            backupHistory = []
            backupHistoryError = safeMessage(error)
        }
    }

    func openBackupRecord(_ record: GitHubBackupHistoryRecord) {
        guard let url = URL(string: record.htmlURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLastBackupOnGitHub() {
        guard let backupLastURL, let url = URL(string: backupLastURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func uploadBackup() async {
        guard !isUploadingBackup else { return }
        guard let backupDraft else {
            backupError = "请先生成备份预览。"
            return
        }
        guard case .signedIn = githubBackupConnection else {
            backupError = "请先登录 GitHub。"
            return
        }
        guard let repository = githubBackupRepositories.first(where: { $0.nameWithOwner == backupRepository }) else {
            backupError = "请选择一个私人仓库。"
            return
        }
        isUploadingBackup = true
        backupError = nil
        backupNotice = nil
        backupLastURL = nil
        defer { isUploadingBackup = false }
        do {
            let target = GitHubBackupTarget(
                repository: repository.nameWithOwner,
                branch: repository.defaultBranch
            )
            UserDefaults.standard.set(target.repository, forKey: "backupRepository")
            UserDefaults.standard.set(target.branch, forKey: "backupBranch")
            let result = try await backupService.upload(draft: backupDraft, target: target)
            backupLastURL = result.htmlURL
            backupNotice = result.commitSHA.map { "已上传到 \(result.path)，提交 \($0.prefix(8))。" } ?? "已上传到 \(result.path)。"
            await refreshBackupHistory()
        } catch {
            backupError = safeMessage(error)
        }
    }

    func clearChangeHistory() {
        changeHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "changeHistory")
    }

    private func addChange(
        kind: ChangeKind,
        name: String,
        identifier: String,
        previous: Bool,
        requested: Bool,
        previousState: String? = nil,
        requestedState: String? = nil,
        outcome: ChangeOutcome,
        message: String
    ) {
        changeHistory.insert(
            ChangeRecord(
                kind: kind,
                targetName: DiagnosticRedactor.sanitize(name),
                targetIdentifier: identifier.hasPrefix("/") ? DiagnosticRedactor.pathSummary(identifier) : DiagnosticRedactor.sanitize(identifier),
                workspacePath: workspaceURL.lastPathComponent.isEmpty ? "本机" : workspaceURL.lastPathComponent,
                previousEnabled: previous,
                requestedEnabled: requested,
                previousState: previousState,
                requestedState: requestedState,
                outcome: outcome,
                message: DiagnosticRedactor.sanitize(message)
            ),
            at: 0
        )
        changeHistory = Array(changeHistory.prefix(500))
        if let data = try? JSONEncoder().encode(changeHistory) {
            UserDefaults.standard.set(data, forKey: "changeHistory")
        }
    }

    private func loadChangeHistory() {
        guard let data = UserDefaults.standard.data(forKey: "changeHistory"),
              let records = try? JSONDecoder().decode([ChangeRecord].self, from: data)
        else { return }
        changeHistory = Array(records.prefix(500)).map { record in
            ChangeRecord(
                id: record.id,
                occurredAt: record.occurredAt,
                kind: record.kind,
                targetName: DiagnosticRedactor.sanitize(record.targetName),
                targetIdentifier: record.targetIdentifier.hasPrefix("/") ? DiagnosticRedactor.pathSummary(record.targetIdentifier) : DiagnosticRedactor.sanitize(record.targetIdentifier),
                workspacePath: URL(fileURLWithPath: record.workspacePath).lastPathComponent,
                previousEnabled: record.previousEnabled,
                requestedEnabled: record.requestedEnabled,
                previousState: record.previousState,
                requestedState: record.requestedState,
                outcome: record.outcome,
                message: DiagnosticRedactor.sanitize(record.message)
            )
        }
        if let sanitized = try? JSONEncoder().encode(changeHistory) {
            UserDefaults.standard.set(sanitized, forKey: "changeHistory")
        }
    }

    private func startEventObservationIfNeeded() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, service] in
            for await event in service.events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: AppServerEvent) async {
        guard event.connectionID == activeConnectionID else { return }
        switch event.method {
        case "skills/changed":
            let workspace = workspaceURL
            let generation = workspaceGeneration
            let previousSkillsError = skillsError
            do {
                let refreshed = try await service.listSkills(cwd: workspace, forceReload: true)
                guard workspaceGeneration == generation, workspaceURL == workspace else { return }
                skills = refreshed
                skillsError = nil
                if lastError == previousSkillsError { lastError = nil }
            } catch {
                guard workspaceGeneration == generation, workspaceURL == workspace else { return }
                let message = safeMessage(error)
                skillsError = message
                lastError = message
            }
        case "hook/started", "hook/completed", "hook_started", "hook_completed":
            guard let run = HookRunParser.parse(event: event, ownership: .attached) else {
                lastError = "Codex 发送了当前版本无法解析的 Hook 运行事件；配置状态不受影响。"
                return
            }
            if let index = hookRuns.firstIndex(where: { $0.id == run.id }) {
                hookRuns[index] = run
            } else {
                hookRuns.insert(run, at: 0)
            }
            hookRuns = Array(hookRuns.prefix(200))
        case "client/malformedMessage":
            lastError = "Codex 返回了一条无法解析的消息，其他状态仍可继续使用。"
        case "client/processExited":
            let status = event.params?.objectValue?["status"]?.numberValue.map(Int.init)
            let message = status.map { "Codex App Server 已意外退出（状态码 \($0)）。可以点击重新扫描恢复连接。" }
                ?? "Codex App Server 已意外退出。可以点击重新扫描恢复连接。"
            connectionGeneration += 1
            activeConnectionID = nil
            await service.disconnect()
            lastError = message
            connectionState = .failed(message)
            skills = []
            hooks = []
            hookWarnings = []
            hookRuns = []
            skillsError = message
            hooksError = message
            mcpServers = []
            mcpWarning = nil
            rateLimits = []
            resetCreditsAvailable = nil
            tokenUsageSummary = nil
            dailyTokenUsage = []
            memorySnapshot = nil
            backupDraft = nil
        case "mcpServer/startupStatus/updated":
            // 全量重载期间保留上一轮可用状态，避免把重启过程误显示成其他 MCP 故障。
            guard !isReloadingAllMCP else { return }
            guard let payload = event.params?.objectValue,
                  let name = payload["name"]?.stringValue,
                  let rawStatus = payload["status"]?.stringValue
            else { return }
            let status = MCPStartupStatus(rawValue: rawStatus) ?? .unknown
            let error = payload["error"]?.stringValue.map(DiagnosticRedactor.commandSummary)
            if let index = mcpServers.firstIndex(where: { $0.name == name }) {
                mcpServers[index] = mcpServers[index].updating(startupStatus: status, errorMessage: error)
            }
        case "account/rateLimits/updated":
            Task { await refreshUsage() }
        default:
            break
        }
    }

    private func safeMessage(_ error: Error) -> String {
        DiagnosticRedactor.commandSummary(error.localizedDescription)
    }

    private func ensureConnected() async throws -> CodexServerInfo {
        if case let .connected(info) = connectionState, await service.isConnected() { return info }
        if case .connected = connectionState {
            connectionState = .idle
            activeConnectionID = nil
            hookRuns = []
        }
        let generation = connectionGeneration
        connectionState = .locating
        let preferred = UserDefaults.standard.string(forKey: "codexExecutablePath")
        guard let executableURL = locator.locate(preferredPath: preferred) else {
            connectionState = .failed(AppModelError.codexNotFound.localizedDescription)
            throw AppModelError.codexNotFound
        }
        connectionState = .connecting(executablePath: executableURL.path)
        do {
            let info = try await service.connect(executableURL: executableURL)
            guard connectionGeneration == generation else { throw CancellationError() }
            activeConnectionID = info.connectionID
            connectionState = .connected(info)
            startEventObservationIfNeeded()
            return info
        } catch {
            guard connectionGeneration == generation else { throw error }
            connectionState = .failed(safeMessage(error))
            throw error
        }
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case skills
    case hooks
    case memory
    case usage
    case mcp
    case storage
    case backup
    case history
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .skills: "Skills"
        case .hooks: "Hooks"
        case .memory: "Memory"
        case .usage: "用量"
        case .mcp: "MCP"
        case .storage: "存储"
        case .backup: "备份"
        case .history: "变更记录"
        case .diagnostics: "自检"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .skills: "wand.and.stars"
        case .hooks: "point.3.connected.trianglepath.dotted"
        case .memory: "brain"
        case .usage: "chart.xyaxis.line"
        case .mcp: "server.rack"
        case .storage: "internaldrive"
        case .backup: "arrow.up.doc.on.clipboard"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "checkmark.shield"
        }
    }
}

enum AppModelError: LocalizedError {
    case codexNotFound
    case writeVerificationFailed
    case configurationChangeInProgress

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "没有找到 Codex CLI。请在设置中手动选择 codex 可执行文件。"
        case .writeVerificationFailed:
            "Codex 接受了写入请求，但重新读取后状态没有生效。原状态已保留。"
        case .configurationChangeInProgress:
            "另一项配置正在修改，请等待它完成后再试。"
        }
    }
}

enum HookRunParser {
    static func parse(event: AppServerEvent, ownership: SessionOwnership) -> HookRunRecord? {
        guard let root = event.params?.objectValue,
              let threadID = (root["threadId"] ?? root["thread_id"])?.stringValue,
              let run = root["run"]?.objectValue,
              let id = run["id"]?.stringValue,
              let rawEvent = (run["eventName"] ?? run["event_name"])?.stringValue,
              let statusRaw = run["status"]?.stringValue,
              let startedNumber = (run["startedAt"] ?? run["started_at"])?.numberValue
        else { return nil }

        let entries = run["entries"]?.arrayValue?.prefix(50).compactMap { item -> HookRunEntry? in
            guard let object = item.objectValue,
                  let kind = object["kind"]?.stringValue,
                  let text = object["text"]?.stringValue
            else { return nil }
            return HookRunEntry(
                kind: DiagnosticRedactor.sanitize(kind),
                text: DiagnosticRedactor.sanitize(text)
            )
        } ?? []

        return HookRunRecord(
            id: id,
            threadID: threadID,
            turnID: (root["turnId"] ?? root["turn_id"])?.stringValue,
            event: HookEvent(protocolValue: rawEvent),
            rawEventName: rawEvent,
            status: HookRunStatus(rawValue: statusRaw) ?? .unknown,
            startedAt: date(from: startedNumber),
            completedAt: (run["completedAt"] ?? run["completed_at"])?.numberValue.map(date(from:)),
            durationMilliseconds: (run["durationMs"] ?? run["duration_ms"])?.numberValue.map(Int.init),
            entries: entries,
            sessionOwnership: ownership
        )
    }

    private static func date(from value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}
