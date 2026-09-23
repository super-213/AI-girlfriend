import Foundation

enum SensitiveDataRedactor {
    static let placeholder = "<redacted>"

    static func redact(_ value: String, secrets: [String] = []) -> String {
        var result = value
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }

        let patterns = [
            #"(?i)(bearer\s+)[^\s\"',}]+"#,
            #"(?i)((?:api[_-]?key|authorization)\s*[:=]\s*[\"']?)[^\s\"',}&]+"#,
            #"\b(?:sk|key)-[A-Za-z0-9_\-]{8,}\b"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1" + placeholder
            )
        }
        return result
    }
}
