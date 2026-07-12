import Foundation

actor CodexService {
    nonisolated var events: AsyncStream<AppServerEvent> { transport.events }

    private let transport = AppServerTransport()
    private var serverInfo: CodexServerInfo?

    func connect(executableURL: URL, environment: [String: String] = [:]) async throws -> CodexServerInfo {
        if let serverInfo { return serverInfo }

        do {
            try await transport.start(executableURL: executableURL, environment: environment)
            let response: InitializeResponse = try await transport.request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("skill_lens"),
                        "title": .string("Skill Lens"),
                        "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(false),
                        "requestAttestation": .bool(false)
                    ])
                ])
            )
            try await transport.sendNotification(method: "initialized", params: .object([:]))

            let info = CodexServerInfo(
                userAgent: response.userAgent,
                codexHome: response.codexHome,
                platformFamily: response.platformFamily,
                platformOS: response.platformOS,
                executablePath: executableURL.path
            )
            serverInfo = info
            return info
        } catch {
            await transport.stop()
            throw error
        }
    }

    func listSkills(cwd: URL, forceReload: Bool = false) async throws -> [SkillRecord] {
        let response: SkillsListResponse = try await transport.request(
            method: "skills/list",
            params: .object([
                "cwds": .array([.string(cwd.path)]),
                "forceReload": .bool(forceReload)
            ])
        )
        guard let entry = response.data.first(where: { $0.cwd == cwd.path }) ?? response.data.first else {
            return []
        }
        return entry.skills
            .map { ProtocolMapper.skill($0, errors: entry.errors) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func listHooks(cwd: URL) async throws -> (hooks: [HookRecord], warnings: [String]) {
        let response: HooksListResponse = try await transport.request(
            method: "hooks/list",
            params: .object(["cwds": .array([.string(cwd.path)])])
        )
        guard let entry = response.data.first(where: { $0.cwd == cwd.path }) ?? response.data.first else {
            return ([], [])
        }
        let errors = entry.errors.map { "\($0.path)：\($0.message)" }
        return (
            entry.hooks.map(ProtocolMapper.hook).sorted { $0.displayOrder < $1.displayOrder },
            entry.warnings + errors
        )
    }

    func setSkillEnabled(path: String, enabled: Bool) async throws {
        let _: EmptyResponse = try await transport.request(
            method: "skills/config/write",
            params: .object([
                "path": .string(path),
                "enabled": .bool(enabled)
            ])
        )
    }

    func setHookEnabled(key: String, enabled: Bool, cwd: URL) async throws {
        guard Self.isSafeHookKey(key) else { throw CodexServiceError.unsafeHookKey }

        let before: ConfigReadResponse = try await transport.request(
            method: "config/read",
            params: .object([
                "cwd": .string(cwd.path),
                "includeLayers": .bool(true)
            ])
        )
        guard let userLayer = before.layers?.first(where: { $0.sourceType == "user" }) else {
            throw CodexServiceError.userConfigLayerMissing
        }

        let response: ConfigBatchWriteResponse = try await transport.request(
            method: "config/batchWrite",
            params: .object([
                "edits": .array([
                    .object([
                        "keyPath": .string("hooks.state.\(key).enabled"),
                        "value": .bool(enabled),
                        "mergeStrategy": .string("upsert")
                    ])
                ]),
                "expectedVersion": .string(userLayer.version),
                "reloadUserConfig": .bool(true)
            ])
        )
        guard response.status == "ok" else { throw CodexServiceError.writeRejected }
    }

    func disconnect() async {
        await transport.stop()
        serverInfo = nil
    }

    static func isSafeHookKey(_ key: String) -> Bool {
        !key.isEmpty && key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}

private struct EmptyResponse: Codable, Sendable { }

enum CodexServiceError: LocalizedError, Sendable {
    case unsafeHookKey
    case userConfigLayerMissing
    case writeRejected
    case managedHook
    case writeVerificationFailed

    var errorDescription: String? {
        switch self {
        case .unsafeHookKey: "该 Hook 的标识包含不支持的字符，为避免写错配置，Skill Lens 将它保持为只读。"
        case .userConfigLayerMissing: "Codex 没有返回可写的用户配置层。"
        case .writeRejected: "Codex 没有确认配置写入成功。"
        case .managedHook: "该 Hook 由系统或管理员管理，不能在这里修改。"
        case .writeVerificationFailed: "Codex 接受了写入，但重新读取后 Hook 状态没有生效。"
        }
    }
}
