import XCTest
@testable import SkillLens

final class ProtocolDecodingTests: XCTestCase {
    func testInitializeResponseAcceptsPlatformOsSpelling() throws {
        let data = Data(#"{"userAgent":"Codex/0.142.5","codexHome":"/tmp/codex","platformFamily":"unix","platformOs":"macos"}"#.utf8)
        let response = try JSONDecoder().decode(InitializeResponse.self, from: data)
        XCTAssertEqual(response.platformOS, "macos")
    }

    func testSkillsListResponseDecodesUnknownFields() throws {
        let data = Data(#"""
        {
          "data": [{
            "cwd": "/tmp/project",
            "errors": [],
            "skills": [{
              "name": "reporting",
              "description": "Build a report",
              "path": "/tmp/reporting/SKILL.md",
              "scope": "user",
              "enabled": true,
              "futureField": "ignored"
            }]
          }]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(SkillsListResponse.self, from: data)

        XCTAssertEqual(response.data.first?.skills.first?.name, "reporting")
        XCTAssertEqual(response.data.first?.skills.first?.enabled, true)
    }

    func testHookMetadataDecodesCurrentSchema() throws {
        let data = Data(#"""
        {
          "data": [{
            "cwd": "/tmp/project",
            "errors": [],
            "warnings": [],
            "hooks": [{
              "key": "pre-check",
              "eventName": "preToolUse",
              "handlerType": "command",
              "matcher": "Bash",
              "command": "/usr/bin/true",
              "timeoutSec": 30,
              "statusMessage": "Checking",
              "sourcePath": "/tmp/hooks.json",
              "source": "user",
              "pluginId": null,
              "displayOrder": 0,
              "enabled": true,
              "isManaged": false,
              "currentHash": "abc",
              "trustStatus": "trusted"
            }]
          }]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(HooksListResponse.self, from: data)
        let wire = try XCTUnwrap(response.data.first?.hooks.first)
        let mapped = ProtocolMapper.hook(wire)

        XCTAssertEqual(mapped.event, .preToolUse)
        XCTAssertEqual(mapped.runnableState, .ready)
    }

    func testRateLimitsAndUsageDecodeOfficialPayloads() throws {
        let rateData = Data(#"{"rateLimits":{"limitId":"codex","limitName":null,"planType":"pro","primary":{"usedPercent":27,"windowDurationMins":300,"resetsAt":1783879000},"secondary":null,"rateLimitReachedType":null,"credits":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":3}}"#.utf8)
        let rate = try JSONDecoder().decode(AccountRateLimitsResponse.self, from: rateData)
        XCTAssertEqual(rate.rateLimits.primary?.usedPercent, 27)
        XCTAssertEqual(rate.rateLimitResetCredits?.availableCount, 3)

        let usageData = Data(#"{"summary":{"lifetimeTokens":3600000000,"peakDailyTokens":52000000,"longestRunningTurnSec":540,"currentStreakDays":8,"longestStreakDays":14},"dailyUsageBuckets":[{"startDate":"2026-07-12","tokens":12345}]}"#.utf8)
        let usage = try JSONDecoder().decode(AccountTokenUsageResponse.self, from: usageData)
        XCTAssertEqual(usage.summary.lifetimeTokens, 3_600_000_000)
        XCTAssertEqual(usage.dailyUsageBuckets?.first?.tokens, 12_345)
    }

    func testMCPInventoryDecodesWithoutExposingSchemas() throws {
        let data = Data(#"{"data":[{"name":"sample","authStatus":"oAuth","tools":{"search":{"name":"search","title":"Search","description":"Find items","inputSchema":{"type":"object"}}},"resources":[],"resourceTemplates":[],"serverInfo":{"name":"sample","title":"Sample MCP","version":"1.0","description":null,"websiteUrl":"https://example.test"}}],"nextCursor":null}"#.utf8)
        let response = try JSONDecoder().decode(MCPServerStatusListResponse.self, from: data)
        XCTAssertEqual(response.data.first?.tools.count, 1)
        XCTAssertEqual(response.data.first?.authStatus, "oAuth")
    }

    func testNonCriticalCollectionsDefaultWhenCodexOmitsThem() throws {
        let skills = try JSONDecoder().decode(
            SkillsListResponse.self,
            from: Data(#"{"data":[{"cwd":"/tmp/project"}]}"#.utf8)
        )
        XCTAssertEqual(skills.data.first?.errors.count, 0)
        XCTAssertEqual(skills.data.first?.skills.count, 0)

        let hooks = try JSONDecoder().decode(
            HooksListResponse.self,
            from: Data(#"{"data":[{"cwd":"/tmp/project","hooks":[{"key":"future","eventName":"futureEvent"}]}]}"#.utf8)
        )
        let hook = try XCTUnwrap(hooks.data.first?.hooks.first)
        XCTAssertEqual(hook.handlerType, "unknown")
        XCTAssertEqual(hook.trustStatus, "unknown")

        let mcp = try JSONDecoder().decode(
            MCPServerStatusListResponse.self,
            from: Data(#"{"data":[{"name":"sample"}],"nextCursor":null}"#.utf8)
        )
        XCTAssertEqual(mcp.data.first?.tools.count, 0)
        XCTAssertEqual(mcp.data.first?.resources.count, 0)
    }
}
