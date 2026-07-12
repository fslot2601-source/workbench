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
    var hookRuns: [HookRunRecord] = []
    var rateLimits: [RateLimitRecord] = []
    var resetCreditsAvailable: Int?
    var tokenUsageSummary: TokenUsageSummary?
    var dailyTokenUsage: [DailyTokenUsage] = []
    var usageRefreshedAt: Date?
    var usageError: String?
    var mcpServers: [MCPRecord] = []
    var mcpError: String?
    var storageRecords: [StorageRecord] = []
    var storageError: String?
    var storageNotice: String?
    var changeHistory: [ChangeRecord] = []
    var isRefreshing = false
    var isRefreshingUsage = false
    var isRefreshingMCP = false
    var isScanningStorage = false
    var isClearingStorage = false
    var isChangingConfiguration = false
    var hasCompletedInitialRefresh = false
    var lastError: String?

    private let service = CodexService()
    private let locator = CodexExecutableLocator()
    private let storageService = CodexStorageService()
    private var eventTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private var workspaceGeneration = 0
    private var connectionGeneration = 0
    private var activeRefreshID: UUID?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "workspacePath"), !saved.isEmpty {
            workspaceURL = URL(fileURLWithPath: saved).standardizedFileURL
        } else {
            workspaceURL = FileManager.default.homeDirectoryForCurrentUser
        }
        loadChangeHistory()
    }

    func bootstrap() async {
        if hasBootstrapped {
            if case .failed = connectionState { await refresh(forceReload: true) }
            return
        }
        hasBootstrapped = true
        await refresh(forceReload: true)
    }

    func refresh(forceReload: Bool = false) async {
        let requestID = UUID()
        let generation = workspaceGeneration
        let workspace = workspaceURL
        activeRefreshID = requestID
        isRefreshing = true
        lastError = nil
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
            } catch {
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                skills = []
                partialFailures.append("Skills：\(safeMessage(error))")
            }
            do {
                let hookResult = try await service.listHooks(cwd: workspace)
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                hooks = hookResult.hooks
                hookWarnings = hookResult.warnings
            } catch {
                guard activeRefreshID == requestID,
                      workspaceGeneration == generation,
                      workspaceURL == workspace
                else { return }
                hooks = []
                hookWarnings = []
                partialFailures.append("Hooks：\(safeMessage(error))")
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
        hookRuns = []
        mcpServers = []
        mcpError = nil
        UserDefaults.standard.set(workspaceURL.path, forKey: "workspacePath")
        Task { await refresh(forceReload: true) }
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
            await service.disconnect()
            connectionState = .idle
            await refresh(forceReload: true)
        }
    }

    func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func setSkill(_ skill: SkillRecord, enabled: Bool) async {
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
            try await service.setSkillEnabled(skill, enabled: enabled, cwd: workspace)
            let refreshed = try await service.listSkills(cwd: workspace, forceReload: true)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            guard refreshed.first(where: { $0.path == skill.path })?.isEnabled == enabled else {
                throw AppModelError.writeVerificationFailed
            }
            skills = refreshed
            addChange(
                kind: .skill,
                name: skill.displayName,
                identifier: skill.path,
                previous: skill.isEnabled,
                requested: enabled,
                outcome: .verified,
                message: "Codex 已写入，并重新读取确认状态生效。"
            )
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            lastError = safeMessage(error)
            addChange(
                kind: .skill,
                name: skill.displayName,
                identifier: skill.path,
                previous: skill.isEnabled,
                requested: enabled,
                outcome: .failed,
                message: safeMessage(error)
            )
        }
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
                name: hook.event.title,
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
                name: hook.event.title,
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

    func refreshMCP() async {
        guard !isRefreshingMCP else { return }
        let workspace = workspaceURL
        let generation = workspaceGeneration
        isRefreshingMCP = true
        mcpError = nil
        defer { isRefreshingMCP = false }
        do {
            _ = try await ensureConnected()
            let records = try await service.listMCPServers(cwd: workspace)
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpServers = records
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpServers = []
            mcpError = safeMessage(error)
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
            await refreshMCP()
            guard mcpServers.first(where: { $0.name == server.name })?.isEnabled == enabled else {
                throw CodexServiceError.writeVerificationFailed
            }
            addChange(
                kind: .mcp,
                name: server.displayName,
                identifier: server.name,
                previous: server.isEnabled,
                requested: enabled,
                outcome: .verified,
                message: "Codex 配置版本校验通过，MCP 配置已重新加载并验证。"
            )
        } catch {
            guard workspaceGeneration == generation, workspaceURL == workspace else { return }
            mcpError = safeMessage(error)
            addChange(
                kind: .mcp,
                name: server.displayName,
                identifier: server.name,
                previous: server.isEnabled,
                requested: enabled,
                outcome: .failed,
                message: safeMessage(error)
            )
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
        guard record.kind.cleanable, !isClearingStorage else { return }
        isClearingStorage = true
        storageError = nil
        defer { isClearingStorage = false }
        do {
            let info = try await ensureConnected()
            let home = URL(fileURLWithPath: info.codexHome)
            connectionGeneration += 1
            await service.disconnect()
            connectionState = .idle
            try await storageService.clear(record: record, codexHome: home)
            storageRecords = await storageService.scan(codexHome: home)
            storageNotice = "缓存已安全清理。会话、配置、Skills、插件和数据库没有被修改。"
            await refresh(forceReload: true)
        } catch {
            storageError = safeMessage(error)
            if case .connected = connectionState { } else { await refresh(forceReload: false) }
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
        switch event.method {
        case "skills/changed":
            let workspace = workspaceURL
            let generation = workspaceGeneration
            do {
                let refreshed = try await service.listSkills(cwd: workspace, forceReload: true)
                guard workspaceGeneration == generation, workspaceURL == workspace else { return }
                skills = refreshed
            } catch {
                guard workspaceGeneration == generation, workspaceURL == workspace else { return }
                lastError = safeMessage(error)
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
            await service.disconnect()
            lastError = message
            connectionState = .failed(message)
            skills = []
            hooks = []
            hookWarnings = []
            mcpServers = []
            rateLimits = []
            resetCreditsAvailable = nil
            tokenUsageSummary = nil
            dailyTokenUsage = []
        case "mcpServer/startupStatus/updated":
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
        if case .connected = connectionState { connectionState = .idle }
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

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard
    case skills
    case hooks
    case usage
    case mcp
    case storage
    case history
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .skills: "Skills"
        case .hooks: "Hooks"
        case .usage: "用量"
        case .mcp: "MCP"
        case .storage: "存储"
        case .history: "变更记录"
        case .diagnostics: "诊断"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .skills: "wand.and.stars"
        case .hooks: "point.3.connected.trianglepath.dotted"
        case .usage: "chart.xyaxis.line"
        case .mcp: "server.rack"
        case .storage: "internaldrive"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
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
            "没有找到 Codex CLI。请在诊断页手动选择 codex 可执行文件。"
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
