import Foundation
import XCTest
@testable import SkillLens

final class StorageSafetyTests: XCTestCase {
    func testScanProtectsUserDataAndOnlyAllowsCache() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 1024).write(to: home.appending(path: "cache/item.bin"))
        try Data(repeating: 2, count: 2048).write(to: home.appending(path: "sessions/session.jsonl"))

        let service = CodexStorageService()
        let records = await service.scan(codexHome: home)
        let cache = try XCTUnwrap(records.first { $0.kind == .cache })
        let sessions = try XCTUnwrap(records.first { $0.kind == .sessions })
        XCTAssertTrue(cache.kind.cleanable)
        XCTAssertFalse(sessions.kind.cleanable)
        XCTAssertGreaterThan(cache.sizeBytes, 0)
    }

    func testClearOnlyRemovesCacheAfterUnchangedRescan() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 1024).write(to: home.appending(path: "cache/item.bin"))
        try Data(repeating: 2, count: 1024).write(to: home.appending(path: "sessions/session.jsonl"))

        let service = CodexStorageService()
        let records = await service.scan(codexHome: home)
        let cache = try XCTUnwrap(records.first { $0.kind == .cache })
        try await service.clear(record: cache, codexHome: home)

        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "sessions/session.jsonl").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "cache").path), [])
    }

    func testClearCancelsWhenCacheChangedAfterScan() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 1024).write(to: home.appending(path: "cache/first.bin"))
        let service = CodexStorageService()
        let records = await service.scan(codexHome: home)
        let cache = try XCTUnwrap(records.first { $0.kind == .cache })
        try Data(repeating: 2, count: 1024).write(to: home.appending(path: "cache/second.bin"))

        do {
            try await service.clear(record: cache, codexHome: home)
            XCTFail("Expected changedSinceScan")
        } catch CodexStorageError.changedSinceScan {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "cache/first.bin").path))
        }
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "skilllens-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "cache"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "sessions"), withIntermediateDirectories: true)
        return home
    }
}
