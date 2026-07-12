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
}
