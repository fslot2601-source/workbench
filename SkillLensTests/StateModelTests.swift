import XCTest
@testable import SkillLens

final class StateModelTests: XCTestCase {
    func testHookEventAcceptsCamelAndSnakeCase() {
        XCTAssertEqual(HookEvent(protocolValue: "preToolUse"), .preToolUse)
        XCTAssertEqual(HookEvent(protocolValue: "pre_tool_use"), .preToolUse)
        XCTAssertEqual(HookEvent(protocolValue: "subagent-stop"), .subagentStop)
        XCTAssertEqual(HookEvent(protocolValue: "future_event"), .unknown)
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
}
