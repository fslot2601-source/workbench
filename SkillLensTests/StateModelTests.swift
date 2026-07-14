import XCTest
@testable import SkillLens

final class StateModelTests: XCTestCase {
    func testHookEventAcceptsCamelAndSnakeCase() {
        XCTAssertEqual(HookEvent(protocolValue: "preToolUse"), .preToolUse)
        XCTAssertEqual(HookEvent(protocolValue: "pre_tool_use"), .preToolUse)
        XCTAssertEqual(HookEvent(protocolValue: "subagent-stop"), .subagentStop)
        XCTAssertEqual(HookEvent(protocolValue: "future_event"), .unknown)
    }

    func testHookPlainLanguageExplainsTriggerMatcherAndEffect() {
        let hook = makeHook(
            event: .preToolUse,
            matcher: nil,
            command: "/Users/example/.codex/hooks/safety-net-pretooluse.sh"
        )

        XCTAssertTrue(hook.triggerSummary.contains("执行前"))
        XCTAssertTrue(hook.matchSummary.contains("终端命令"))
        XCTAssertTrue(hook.matchSummary.contains("MCP"))
        XCTAssertTrue(hook.actionSummary.contains("危险"))
        XCTAssertEqual(hook.effectTitle, "可以阻止或改写")
    }

    func testStopHookIsExplainedAsTurnEndRatherThanTaskDeletion() {
        let hook = makeHook(event: .stop, matcher: "ignored", command: "/usr/bin/true")

        XCTAssertEqual(hook.event.title, "本轮即将结束")
        XCTAssertTrue(hook.triggerSummary.contains("这一轮回答"))
        XCTAssertTrue(hook.matchSummary.contains("每次都会触发"))
        XCTAssertTrue(hook.effectSummary.contains("继续一轮"))
    }

    func testHookActionRecognizesKnownLocalHandlers() {
        XCTAssertTrue(
            makeHook(event: .sessionStart, command: "/tmp/vibe-island-bridge --source codex")
                .actionSummary.contains("Vibe Island")
        )
        XCTAssertTrue(
            makeHook(event: .subagentStart, command: "/tmp/subagent-policy-audit.py")
                .actionSummary.contains("子代理")
        )
    }

    func testHookDisplayNameIdentifiesIndividualHandlerRatherThanOnlyEvent() {
        XCTAssertEqual(
            makeHook(event: .preToolUse, command: "/tmp/safety-net-pretooluse.sh").displayName,
            "Safety Net 安全检查"
        )
        XCTAssertEqual(
            makeHook(event: .preToolUse, command: "/tmp/audit-command.sh").displayName,
            "audit-command"
        )
    }

    func testHookRunParserAcceptsSnakeCaseFields() throws {
        let event = AppServerEvent(
            method: "hook_started",
            params: .object([
                "thread_id": .string("thread-1"),
                "turn_id": .string("turn-1"),
                "run": .object([
                    "id": .string("run-1"),
                    "event_name": .string("pre_tool_use"),
                    "status": .string("running"),
                    "started_at": .number(1_700_000_000),
                    "duration_ms": .number(42),
                    "entries": .array([])
                ])
            ])
        )

        let run = try XCTUnwrap(HookRunParser.parse(event: event, ownership: .owned))
        XCTAssertEqual(run.threadID, "thread-1")
        XCTAssertEqual(run.turnID, "turn-1")
        XCTAssertEqual(run.event, .preToolUse)
        XCTAssertEqual(run.durationMilliseconds, 42)
    }

    func testDisabledSkillWinsOverMissingDependency() {
        let skill = SkillRecord(
            name: "sample",
            displayName: "Sample",
            description: "Sample",
            shortDescription: nil,
            path: "/tmp/sample/SKILL.md",
            scope: .user,
            rawScope: "user",
            isEnabled: false,
            invocationPolicy: .automaticAllowed,
            dependencies: [
                SkillDependency(type: "env_var", value: "TOKEN", summary: nil, availability: .missing)
            ],
            errors: []
        )

        XCTAssertEqual(skill.effectiveState, .disabled)
        XCTAssertFalse(skill.hasProblem)
    }

    func testDisabledSkillWithErrorIsHiddenNotProblem() {
        let skill = SkillRecord(
            name: "hidden",
            displayName: "Hidden",
            description: "Hidden",
            shortDescription: nil,
            path: "/tmp/hidden/SKILL.md",
            scope: .user,
            rawScope: "user",
            isEnabled: false,
            invocationPolicy: .explicitOnly,
            dependencies: [],
            errors: ["Broken metadata"]
        )
        XCTAssertEqual(skill.effectiveState, .disabled)
        XCTAssertFalse(skill.hasProblem)
    }

    func testSkillErrorHasHighestPriority() {
        let skill = SkillRecord(
            name: "sample",
            displayName: "Sample",
            description: "Sample",
            shortDescription: nil,
            path: "/tmp/sample/SKILL.md",
            scope: .user,
            rawScope: "user",
            isEnabled: true,
            invocationPolicy: .explicitOnly,
            dependencies: [],
            errors: ["Invalid frontmatter"]
        )

        XCTAssertEqual(skill.effectiveState, .error)
    }

    func testSkillTranslationPolicyTranslatesEnglishDominantMixedDescriptions() {
        XCTAssertTrue(SkillTranslationPolicy.needsChineseTranslation("Build AI agents on Cloudflare Workers."))
        XCTAssertTrue(SkillTranslationPolicy.needsChineseTranslation("For Liepin applications, de-duplicate against prior 岗位推进 records."))
        XCTAssertTrue(SkillTranslationPolicy.needsChineseTranslation("For personal 数桥 writing, make it looser and more human."))
        XCTAssertFalse(SkillTranslationPolicy.needsChineseTranslation("通过命令行工具操作邮件。"))
        XCTAssertFalse(SkillTranslationPolicy.needsChineseTranslation("通过 Codex 操作本地邮件和附件。"))
        XCTAssertFalse(SkillTranslationPolicy.needsChineseTranslation("MCP"))
        XCTAssertFalse(SkillTranslationPolicy.needsChineseTranslation(""))
    }

    func testSkillModeCombinesEnabledAndInvocationPolicy() {
        func skill(enabled: Bool, policy: SkillInvocationPolicy) -> SkillRecord {
            SkillRecord(
                name: "sample",
                displayName: "Sample",
                description: "Sample skill",
                shortDescription: nil,
                path: "/tmp/sample/SKILL.md",
                scope: .user,
                rawScope: "user",
                isEnabled: enabled,
                invocationPolicy: policy,
                dependencies: [],
                errors: []
            )
        }

        XCTAssertEqual(skill(enabled: true, policy: .automaticAllowed).mode, .implicit)
        XCTAssertEqual(skill(enabled: true, policy: .explicitOnly).mode, .explicit)
        XCTAssertEqual(skill(enabled: false, policy: .automaticAllowed).mode, .hidden)
        XCTAssertEqual(skill(enabled: false, policy: .explicitOnly).mode, .hidden)
    }

    func testMCPRequiresExposedCapabilitiesBeforeItIsEffective() {
        let server = makeMCP(
            inventoryStatus: .available,
            tools: [.init(name: "search", title: "Search", description: "Find items")]
        )

        XCTAssertEqual(server.effectiveState, .effective)
        XCTAssertEqual(server.toolCount, 1)
        XCTAssertEqual(server.healthChecks.last?.title, "真实调用")
        XCTAssertEqual(server.healthChecks.last?.status, .notVerified)
    }

    func testMCPStatusTimeoutKeepsConfigurationButDoesNotClaimAProblem() {
        let server = makeMCP(inventoryStatus: .unavailable("状态接口超时"))

        XCTAssertEqual(server.effectiveState, .statusUnavailable)
        XCTAssertFalse(server.hasProblem)
        XCTAssertEqual(server.healthChecks.first { $0.title == "工具与资源" }?.status, .unknown)
    }

    func testDisabledMCPWinsOverConfigurationAndAuthenticationIssues() {
        let server = makeMCP(
            isEnabled: false,
            authStatus: .notLoggedIn,
            inventoryStatus: .unavailable("状态接口超时"),
            configurationIssue: "启动器不存在"
        )

        XCTAssertEqual(server.effectiveState, .disabled)
        XCTAssertFalse(server.hasProblem)
    }

    func testConnectedMCPWithoutCapabilitiesIsARealProblem() {
        let server = makeMCP(inventoryStatus: .available)

        XCTAssertEqual(server.effectiveState, .connectedNoCapabilities)
        XCTAssertTrue(server.hasProblem)
    }

    func testPendingMCPConfigurationKeepsObservedRuntimeStateUntilReload() {
        let running = makeMCP(
            inventoryStatus: .available,
            tools: [.init(name: "search", title: "Search", description: "Find items")]
        )
        let pendingDisable = running.updating(pendingEnabledState: false)

        XCTAssertEqual(pendingDisable.effectiveState, .effective)
        XCTAssertFalse(pendingDisable.configuredEnabledState)
        XCTAssertTrue(pendingDisable.isReloadPending)
        XCTAssertEqual(pendingDisable.healthChecks.first?.status, .attention)
        XCTAssertTrue(pendingDisable.healthChecks.first?.detail.contains("等待重新加载全部 MCP") == true)
    }

    func testMCPAuthStatusAcceptsCLIAndProtocolSpellings() {
        XCTAssertEqual(MCPAuthStatus(protocolValue: "oAuth"), .oAuth)
        XCTAssertEqual(MCPAuthStatus(protocolValue: "o_auth"), .oAuth)
        XCTAssertEqual(MCPAuthStatus(protocolValue: "not_logged_in"), .notLoggedIn)
    }

    func testMCPConfigurationValidationRejectsBrokenEndpointAndMissingLauncher() {
        XCTAssertNotNil(CodexService.mcpConfigurationIssue(url: "file:///tmp/server", command: nil))
        XCTAssertNotNil(CodexService.mcpConfigurationIssue(url: nil, command: "/definitely/missing/server"))
        XCTAssertNil(CodexService.mcpConfigurationIssue(url: "https://example.test/mcp", command: nil))
        XCTAssertNil(CodexService.mcpConfigurationIssue(url: nil, command: "npx"))
    }

    func testManagedHookSourcesCannotBeModified() {
        for source in [HookSource.mdm, .cloudManagedConfig, .legacyManagedConfigFile] {
            let hook = HookRecord(
                key: "managed",
                event: .stop,
                rawEventName: "stop",
                handlerType: .command,
                rawHandlerType: "command",
                matcher: nil,
                command: nil,
                timeoutSeconds: 5,
                statusMessage: nil,
                sourcePath: "/tmp/config.toml",
                source: source,
                rawSource: source.rawValue,
                pluginID: nil,
                displayOrder: 0,
                isEnabled: true,
                isManaged: false,
                currentHash: "hash",
                trustStatus: .trusted,
                rawTrustStatus: "trusted"
            )
            XCTAssertTrue(hook.isEffectivelyManaged)
        }
    }

    private func makeHook(
        event: HookEvent,
        matcher: String? = nil,
        command: String? = nil
    ) -> HookRecord {
        HookRecord(
            key: "test-hook",
            event: event,
            rawEventName: event.rawValue,
            handlerType: .command,
            rawHandlerType: "command",
            matcher: matcher,
            command: command,
            timeoutSeconds: 5,
            statusMessage: nil,
            sourcePath: "/tmp/hooks.json",
            source: .user,
            rawSource: "user",
            pluginID: nil,
            displayOrder: 0,
            isEnabled: true,
            isManaged: false,
            currentHash: "hash",
            trustStatus: .trusted,
            rawTrustStatus: "trusted"
        )
    }

    private func makeMCP(
        isEnabled: Bool = true,
        authStatus: MCPAuthStatus = .unsupported,
        inventoryStatus: MCPInventoryStatus = .notReported,
        tools: [MCPToolRecord] = [],
        configurationIssue: String? = nil
    ) -> MCPRecord {
        MCPRecord(
            name: "sample",
            displayName: "Sample",
            version: "1.0",
            description: "Sample MCP",
            transport: .stdio,
            endpointSummary: "sample-server",
            isConfigured: true,
            isEnabled: isEnabled,
            isRequired: false,
            authStatus: authStatus,
            startupStatus: isEnabled ? .configured : .disabled,
            inventoryStatus: inventoryStatus,
            tools: tools,
            resources: [],
            startupTimeoutSeconds: nil,
            toolTimeoutSeconds: nil,
            configurationIssue: configurationIssue,
            errorMessage: nil,
            checkedAt: Date(timeIntervalSince1970: 0),
            workspacePath: "/tmp",
            canModify: true,
            readOnlyReason: nil
        )
    }
}
