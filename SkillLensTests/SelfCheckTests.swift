import Foundation
import Testing
@testable import SkillLens

@Suite("系统自检语义")
struct SelfCheckTests {
    @Test("只有失败状态会计入真实问题")
    func onlyFailureCountsAsProblem() {
        #expect(SelfCheckStatus.failed.isFailure)
        #expect(!SelfCheckStatus.warning.isFailure)
        #expect(!SelfCheckStatus.notChecked.isFailure)
        #expect(!SelfCheckStatus.checking.isFailure)
        #expect(!SelfCheckStatus.passed.isFailure)
    }

    @Test("停用的 MCP 不会被误报为问题")
    func disabledMCPIsNotAProblem() {
        let record = MCPRecord(
            name: "disabled-server",
            displayName: "Disabled Server",
            version: nil,
            description: nil,
            transport: .stdio,
            endpointSummary: "disabled-server",
            isConfigured: true,
            isEnabled: false,
            isRequired: false,
            authStatus: .unknown,
            startupStatus: .disabled,
            inventoryStatus: .notReported,
            tools: [],
            resources: [],
            startupTimeoutSeconds: nil,
            toolTimeoutSeconds: nil,
            configurationIssue: nil,
            errorMessage: nil,
            checkedAt: Date(timeIntervalSince1970: 0),
            workspacePath: "/tmp",
            canModify: true,
            readOnlyReason: nil,
            pendingEnabledState: nil
        )

        #expect(record.effectiveState == MCPEffectiveState.disabled)
        #expect(!record.hasProblem)
    }
}
