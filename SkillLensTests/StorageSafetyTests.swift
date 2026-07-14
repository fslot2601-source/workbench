import Foundation
import XCTest
@testable import SkillLens

final class StorageSafetyTests: XCTestCase {
    func testScanUsesSafeCautiousAndProtectedCleanupLevels() async throws {
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
        XCTAssertEqual(cache.kind.cleanupLevel, .safe)
        XCTAssertEqual(sessions.kind.cleanupLevel, .protected)
        XCTAssertGreaterThan(cache.sizeBytes, 0)
        XCTAssertEqual(cache.reclaimableItemCount, 1)
    }

    func testClearOnlyRemovesCacheAfterUnchangedRescan() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 1024).write(to: home.appending(path: "cache/item.bin"))
        try Data(repeating: 2, count: 1024).write(to: home.appending(path: "sessions/session.jsonl"))

        let service = CodexStorageService()
        let records = await service.scan(codexHome: home)
        let cache = try XCTUnwrap(records.first { $0.kind == .cache })
        let verifiedRecords = await service.scan(codexHome: home)
        let verifiedCache = try XCTUnwrap(verifiedRecords.first { $0.kind == .cache })
        XCTAssertEqual(cache.sizeBytes, verifiedCache.sizeBytes)
        XCTAssertEqual(cache.itemCount, verifiedCache.itemCount)
        XCTAssertEqual(cache.reclaimableSizeBytes, verifiedCache.reclaimableSizeBytes)
        XCTAssertEqual(cache.reclaimableItemCount, verifiedCache.reclaimableItemCount)
        XCTAssertEqual(cache.cleanupFingerprint, verifiedCache.cleanupFingerprint)
        _ = try await service.clear(record: cache, codexHome: home)

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
            _ = try await service.clear(record: cache, codexHome: home)
            XCTFail("Expected changedSinceScan")
        } catch CodexStorageError.changedSinceScan {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "cache/first.bin").path))
        }
    }

    func testTemporaryAndLogCleanupOnlySelectsOldFiles() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldTemporary = home.appending(path: ".tmp/old.tmp")
        let freshTemporary = home.appending(path: ".tmp/fresh.tmp")
        let oldLog = home.appending(path: "log/old.log")
        let freshLog = home.appending(path: "log/fresh.log")
        for file in [oldTemporary, freshTemporary, oldLog, freshLog] {
            try Data(repeating: 1, count: 64).write(to: file)
        }
        try setModified(oldTemporary, date: now.addingTimeInterval(-2 * 24 * 60 * 60))
        try setModified(freshTemporary, date: now.addingTimeInterval(-60 * 60))
        try setModified(oldLog, date: now.addingTimeInterval(-8 * 24 * 60 * 60))
        try setModified(freshLog, date: now.addingTimeInterval(-2 * 24 * 60 * 60))

        let service = CodexStorageService(disposalMode: .removeImmediatelyForTesting)
        let records = await service.scan(codexHome: home, now: now)
        let temporary = try XCTUnwrap(records.first { $0.kind == .temporary })
        let logs = try XCTUnwrap(records.first { $0.kind == .logs })
        XCTAssertEqual(temporary.reclaimableItemCount, 1)
        XCTAssertEqual(logs.reclaimableItemCount, 1)

        _ = try await service.clear(record: temporary, codexHome: home, now: now)
        _ = try await service.clear(record: logs, codexHome: home, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTemporary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshTemporary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLog.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshLog.path))
    }

    func testArchivedSessionsAreCautiousAndRecreatedAfterCleanup() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 64).write(to: home.appending(path: "archived_sessions/old.jsonl"))
        try Data(repeating: 2, count: 64).write(to: home.appending(path: "sessions/current.jsonl"))

        let service = CodexStorageService(disposalMode: .removeImmediatelyForTesting)
        let records = await service.scan(codexHome: home)
        let archived = try XCTUnwrap(records.first { $0.kind == .archivedSessions })
        XCTAssertEqual(archived.kind.cleanupLevel, .cautious)
        XCTAssertEqual(archived.reclaimableItemCount, 1)

        let result = try await service.clear(record: archived, codexHome: home)
        XCTAssertEqual(result.kind, .archivedSessions)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "archived_sessions").path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "sessions/current.jsonl").path))
    }

    func testProtectedSessionsCannotBeCleaned() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(repeating: 1, count: 64).write(to: home.appending(path: "sessions/current.jsonl"))
        let service = CodexStorageService(disposalMode: .removeImmediatelyForTesting)
        let records = await service.scan(codexHome: home)
        let sessions = try XCTUnwrap(records.first { $0.kind == .sessions })

        do {
            _ = try await service.clear(record: sessions, codexHome: home)
            XCTFail("Expected protectedCategory")
        } catch CodexStorageError.protectedCategory {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "sessions/current.jsonl").path))
        }
    }

    func testClearRejectsSymlinkCodexHome() async throws {
        let realHome = try makeHome()
        let link = FileManager.default.temporaryDirectory.appending(path: "skilllens-storage-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realHome)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: realHome)
        }
        try Data(repeating: 1, count: 64).write(to: realHome.appending(path: "cache/item.bin"))
        let service = CodexStorageService()
        let cache = StorageRecord(
            kind: .cache,
            path: link.appending(path: "cache").path,
            sizeBytes: 0,
            itemCount: 0
        )

        do {
            try await service.clear(record: cache, codexHome: link)
            XCTFail("Expected symbolicLink")
        } catch CodexStorageError.symbolicLink {
            XCTAssertTrue(FileManager.default.fileExists(atPath: realHome.appending(path: "cache/item.bin").path))
        }
    }

    func testClearRejectsCacheThatIsARegularFile() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.removeItem(at: home.appending(path: "cache"))
        try Data(repeating: 1, count: 64).write(to: home.appending(path: "cache"))
        let service = CodexStorageService()
        let records = await service.scan(codexHome: home)
        let cache = try XCTUnwrap(records.first { $0.kind == .cache })

        do {
            _ = try await service.clear(record: cache, codexHome: home)
            XCTFail("Expected notDirectory")
        } catch CodexStorageError.notDirectory {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "cache").path))
        }
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "skilllens-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "cache"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "archived_sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".tmp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "log"), withIntermediateDirectories: true)
        return home
    }

    private func setModified(_ url: URL, date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
