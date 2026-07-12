import Foundation

enum DiagnosticRedactor {
    private static let maximumDisplayLength = 2_000

    static func sanitize(_ text: String) -> String {
        var result = String(text.prefix(maximumDisplayLength))
        let patterns: [(String, String)] = [
            (#"(?i)(--(?:token|password|secret|api[-_]?key|client[-_]?secret|access[-_]?token|refresh[-_]?token))(?:=|\s+)(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#, "$1=••••"),
            (#"(?i)(--header(?:=|\s+))(?:\"[^\"]*\"|'[^']*'|[^\r\n]+)"#, "$1••••"),
            (#"(?i)\b([A-Z0-9_]*(?:TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY|ACCESS_KEY|AUTH|COOKIE|SESSION)[A-Z0-9_]*=)(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#, "$1••••"),
            (#"(?i)(bearer\s+)([A-Za-z0-9._~+/=-]+)"#, "$1••••"),
            (#"(?i)([\"']?(?:token|password|secret|api[-_]?key|client[-_]?secret|access[-_]?token|refresh[-_]?token|authorization|cookie|private[-_]?key)[\"']?\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\"',\s}\]]+)"#, "$1••••"),
            (#"(?i)([?&](?:access_token|refresh_token|token|api_key|client_secret|signature)=)([^&#\s]+)"#, "$1••••"),
            (#"(?i)(://[^/@:\s]+:)([^@/\s]+)(@)"#, "$1••••$3")
        ]
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        if text.count > maximumDisplayLength { result += "…（内容已截断）" }
        return result
    }

    static func commandSummary(_ command: String?) -> String {
        guard let command, !command.isEmpty else { return "未提供命令" }
        return sanitize(command)
    }

    static func pathSummary(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parts = url.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return "本机路径" }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    static func dependencyValue(type: String, value: String) -> String {
        switch type {
        case "env_var":
            return value.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        case "url", "http":
            guard let components = URLComponents(string: value), let scheme = components.scheme else {
                return "远程地址（详细信息已隐藏）"
            }
            let host = components.host ?? "未公开主机"
            let port = components.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        case "command", "executable":
            let executable = value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? value
            return URL(fileURLWithPath: executable).lastPathComponent
        default:
            return sanitize(value)
        }
    }
}
