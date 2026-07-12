import Foundation

enum DiagnosticRedactor {
    static func commandSummary(_ command: String?) -> String {
        guard let command, !command.isEmpty else { return "未提供命令" }
        var result = command
        let patterns = [
            #"(?i)(--(?:token|password|secret|api[-_]?key)\s+)([^\s]+)"#,
            #"(?i)\b([A-Z0-9_]*(?:TOKEN|PASSWORD|SECRET|API_KEY)[A-Z0-9_]*=)([^\s]+)"#,
            #"(?i)(bearer\s+)([A-Za-z0-9._~+/=-]+)"#,
            #"(?i)([\"']?(?:token|password|secret|api[-_]?key)[\"']?\s*[:=]\s*[\"']?)([^\"',\s}\]]+)"#,
            #"(?i)([?&](?:access_token|token|api_key)=)([^&#\s]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1••••"
            )
        }
        return result
    }
}
