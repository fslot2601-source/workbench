import Foundation

enum SkillMetadataResolver {
    private static let maximumMetadataBytes = 256 * 1_024

    static func invocationPolicy(skillPath: String) -> SkillInvocationPolicy {
        let skillURL = URL(fileURLWithPath: skillPath).standardizedFileURL
        let skillDirectory = skillURL.deletingLastPathComponent()

        let jsonURL = skillDirectory.appendingPathComponent("SKILL.json")
        if let policy = policyFromJSON(at: jsonURL) {
            return policy
        }

        let yamlURL = skillDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("openai.yaml")
        if let policy = policyFromYAML(at: yamlURL) {
            return policy
        }

        let ymlURL = yamlURL.deletingPathExtension().appendingPathExtension("yml")
        if let policy = policyFromYAML(at: ymlURL) {
            return policy
        }

        // Codex documents implicit invocation as enabled by default.
        return .automaticAllowed
    }

    static func writeInvocationPolicy(
        skillPath: String,
        policy: SkillInvocationPolicy
    ) throws -> SkillMetadataMutation {
        guard policy == .automaticAllowed || policy == .explicitOnly else {
            throw SkillMetadataError.unsupportedPolicy
        }

        let fileManager = FileManager.default
        let skillURL = URL(fileURLWithPath: skillPath).standardizedFileURL
        let skillValues = try skillURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard skillValues.isRegularFile == true, skillValues.isSymbolicLink != true else {
            throw SkillMetadataError.invalidSkillFile
        }

        let skillDirectory = skillURL.deletingLastPathComponent()
        let agentsDirectory = skillDirectory.appendingPathComponent("agents", isDirectory: true)
        var createdAgentsDirectory = false
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: agentsDirectory.path, isDirectory: &isDirectory) {
            let values = try agentsDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard isDirectory.boolValue, values.isDirectory == true, values.isSymbolicLink != true else {
                throw SkillMetadataError.unsafeMetadataPath
            }
        } else {
            try fileManager.createDirectory(at: agentsDirectory, withIntermediateDirectories: false)
            createdAgentsDirectory = true
        }

        do {
            let yamlURL = agentsDirectory.appendingPathComponent("openai.yaml")
            let ymlURL = agentsDirectory.appendingPathComponent("openai.yml")
            let metadataURL: URL
            if fileManager.fileExists(atPath: yamlURL.path) {
                metadataURL = yamlURL
            } else if fileManager.fileExists(atPath: ymlURL.path) {
                metadataURL = ymlURL
            } else {
                metadataURL = yamlURL
            }

            let previousContents: Data?
            if fileManager.fileExists(atPath: metadataURL.path) {
                let values = try metadataURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let size = values.fileSize,
                      size <= maximumMetadataBytes
                else { throw SkillMetadataError.unsafeMetadataPath }
                previousContents = try Data(contentsOf: metadataURL)
            } else {
                previousContents = nil
            }

            let existing = try previousContents.map { data -> String in
                guard let text = String(data: data, encoding: .utf8) else {
                    throw SkillMetadataError.invalidEncoding
                }
                return text
            } ?? ""
            let updated = updatingYAML(existing, allowImplicit: policy == .automaticAllowed)
            guard let updatedData = updated.data(using: .utf8), updatedData.count <= maximumMetadataBytes else {
                throw SkillMetadataError.metadataTooLarge
            }
            try updatedData.write(to: metadataURL, options: .atomic)

            return SkillMetadataMutation(
                metadataURL: metadataURL,
                previousContents: previousContents,
                createdAgentsDirectory: createdAgentsDirectory
            )
        } catch {
            if createdAgentsDirectory,
               (try? fileManager.contentsOfDirectory(atPath: agentsDirectory.path).isEmpty) == true {
                try? fileManager.removeItem(at: agentsDirectory)
            }
            throw error
        }
    }

    static func restore(_ mutation: SkillMetadataMutation) throws {
        let fileManager = FileManager.default
        if let previousContents = mutation.previousContents {
            try previousContents.write(to: mutation.metadataURL, options: .atomic)
        } else if fileManager.fileExists(atPath: mutation.metadataURL.path) {
            try fileManager.removeItem(at: mutation.metadataURL)
        }

        if mutation.createdAgentsDirectory {
            let agentsDirectory = mutation.metadataURL.deletingLastPathComponent()
            let remaining = try fileManager.contentsOfDirectory(atPath: agentsDirectory.path)
            if remaining.isEmpty {
                try fileManager.removeItem(at: agentsDirectory)
            }
        }
    }

    private static func updatingYAML(_ contents: String, allowImplicit: Bool) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let replacementValue = allowImplicit ? "true" : "false"

        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("allow_implicit_invocation:")
        }) {
            let indentation = String(lines[index].prefix { $0 == " " || $0 == "\t" })
            lines[index] = "\(indentation)allow_implicit_invocation: \(replacementValue)"
        } else if let policyIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "policy:"
        }) {
            let indentation = String(lines[policyIndex].prefix { $0 == " " || $0 == "\t" }) + "  "
            lines.insert("\(indentation)allow_implicit_invocation: \(replacementValue)", at: policyIndex + 1)
        } else {
            if !lines.isEmpty, lines.last != "" { lines.append("") }
            lines.append("policy:")
            lines.append("  allow_implicit_invocation: \(replacementValue)")
        }

        while lines.count > 1, lines.last == "", lines[lines.count - 2] == "" {
            lines.removeLast()
        }
        if lines.last != "" { lines.append("") }
        return lines.joined(separator: "\n")
    }

    private static func policyFromJSON(at url: URL) -> SkillInvocationPolicy? {
        guard let data = boundedContents(of: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let policy = root["policy"] as? [String: Any],
              let value = policy["allow_implicit_invocation"] as? Bool
        else { return nil }
        return value ? .automaticAllowed : .explicitOnly
    }

    private static func policyFromYAML(at url: URL) -> SkillInvocationPolicy? {
        guard let data = boundedContents(of: url),
              let contents = String(data: data, encoding: .utf8)
        else { return nil }
        for line in contents.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("allow_implicit_invocation:") else { continue }
            let value = trimmed
                .split(separator: ":", maxSplits: 1)
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if value == "true" { return .automaticAllowed }
            if value == "false" { return .explicitOnly }
        }
        return nil
    }

    private static func boundedContents(of url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maximumMetadataBytes
        else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

struct SkillMetadataMutation: Sendable {
    let metadataURL: URL
    let previousContents: Data?
    let createdAgentsDirectory: Bool
}

enum SkillMetadataError: LocalizedError, Sendable {
    case unsupportedPolicy
    case invalidSkillFile
    case unsafeMetadataPath
    case invalidEncoding
    case metadataTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedPolicy: "该 Skill 的调用方式无法安全修改。"
        case .invalidSkillFile: "Skill 不是可安全修改的普通文件。"
        case .unsafeMetadataPath: "Skill 的元数据路径不安全或不是普通文件，已拒绝写入。"
        case .invalidEncoding: "Skill 的 openai.yaml 不是有效的 UTF-8 文本。"
        case .metadataTooLarge: "Skill 的元数据文件过大，已拒绝写入。"
        }
    }
}
