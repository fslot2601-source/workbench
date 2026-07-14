import Foundation

struct BackupDraft: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let codexHomePath: String
    let includedFiles: [BackupFile]
    let excludedItems: [String]
    let redactionCount: Int
    let payload: JSONValue

    var fileCount: Int { includedFiles.count }
    var byteCount: Int { includedFiles.reduce(0) { $0 + $1.content.utf8.count } }
}

struct BackupFile: Identifiable, Sendable, Equatable {
    let relativePath: String
    let content: String

    var id: String { relativePath }
}

struct BackupOptions: Sendable, Equatable {
    var includeAgents = true
    var includeRules = true
    var includeProjectInstructions = true
    var includeCuratedMemory = false
}

struct GitHubBackupTarget: Sendable, Equatable {
    let repository: String
    let branch: String
}

struct GitHubBackupAccount: Sendable, Equatable {
    let login: String
    let credentialStorageDescription: String
}

struct GitHubBackupRepository: Identifiable, Sendable, Equatable {
    let nameWithOwner: String
    let defaultBranch: String
    let url: String

    var id: String { nameWithOwner }
}

struct GitHubBackupHistoryRecord: Identifiable, Sendable, Equatable {
    let commitSHA: String
    let createdAt: Date
    let message: String
    let htmlURL: String

    var id: String { commitSHA }
}

enum GitHubBackupConnectionState: Sendable, Equatable {
    case notChecked
    case checking
    case cliMissing
    case signedOut
    case signedIn(GitHubBackupAccount)
}

struct GitHubBackupResult: Sendable, Equatable {
    let path: String
    let commitSHA: String?
    let htmlURL: String?
}
