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
