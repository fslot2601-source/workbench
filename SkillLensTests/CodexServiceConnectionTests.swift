import Foundation
import XCTest
@testable import SkillLens

final class CodexServiceConnectionTests: XCTestCase {
    func testConcurrentConnectCallsShareOneAppServerProcess() async throws {
        let fixture = try makeServer()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = CodexService()
        let environment = ["SKILLLENS_START_COUNTER": fixture.counter.path]

        async let first = service.connect(executableURL: fixture.executable, environment: environment)
        async let second = service.connect(executableURL: fixture.executable, environment: environment)
        let (firstInfo, secondInfo) = try await (first, second)

        XCTAssertEqual(firstInfo, secondInfo)
        let starts = try String(contentsOf: fixture.counter, encoding: .utf8)
            .split(whereSeparator: \Character.isNewline)
        XCTAssertEqual(starts.count, 1)
        let isConnected = await service.isConnected()
        XCTAssertTrue(isConnected)
        await service.disconnect()
    }

    private func makeServer() throws -> (
        directory: URL,
        executable: URL,
        counter: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "skilllens-connect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appending(path: "fake-codex")
        let counter = directory.appending(path: "starts.txt")
        let script = #"""
        #!/bin/sh
        printf 'started\n' >> "$SKILLLENS_START_COUNTER"
        while IFS= read -r line; do
          id=$(printf "%s" "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
          case "$line" in
            *'"method":"initialize"'*)
              sleep 1
              printf '{"id":%s,"result":{"userAgent":"fake-codex","codexHome":"/tmp/skilllens-fake-home","platformFamily":"unix","platformOs":"macos"}}\n' "$id"
              ;;
          esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable, counter)
    }
}
