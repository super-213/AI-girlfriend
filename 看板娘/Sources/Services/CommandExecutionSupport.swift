//
//  CommandExecutionSupport.swift
//  桌面宠物应用
//
//  AI 输出命令的解析、校验与执行工具
//

import Foundation

enum CommandExecutionSupport {
    static func extractCommand(from text: String) -> String? {
        if let command = extractCommandByToken(text, token: "命令:") {
            return command
        }

        let tags = ["[命令]", "[系统指令]", "[系统命令]", "[command]"]

        for tag in tags {
            if let range = text.range(of: tag) {
                let tail = text[range.upperBound...]
                let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
                let command = line.map(String.init) ?? String(tail)
                let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        let lines = text.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for tag in tags {
                if trimmed.hasPrefix(tag) {
                    let cleaned = trimmed.replacingOccurrences(of: tag, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }

        return extractCommandWithoutTag(from: text)
    }

    static func hasCommandTag(in text: String) -> Bool {
        let tags = ["[命令]", "[系统指令]", "[系统命令]", "[command]"]
        return tags.contains { text.contains($0) }
    }

    static func isCompletionReply(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("完成:") || trimmed.hasPrefix("[完成]")
    }

    static func normalizeCommand(_ command: String, basedOn input: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let inputLower = input.lowercased()
        let listingIntent = input.contains("目录") || input.contains("文件") || input.contains("列表")
            || inputLower.contains("list")

        if listingIntent, lower.hasPrefix("ls -l"), !lower.contains(" -a") {
            if lower.hasPrefix("ls -lh") {
                return trimmed.replacingOccurrences(of: "ls -lh", with: "ls -lha")
            }
            return trimmed.replacingOccurrences(of: "ls -l", with: "ls -la")
        }

        return trimmed
    }

    static func isCommandSafe(_ command: String) -> Bool {
        let lower = command.lowercased()
        let normalized = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowPrefixes = [
            "ls", "pwd", "cat", "zip", "tar", "cp", "mv", "mkdir", "rmdir"
        ]

        if allowPrefixes.contains(where: { normalized.hasPrefix($0 + " ") || normalized == $0 }) {
            return !lower.contains("rm -rf") && !lower.contains("sudo")
        }

        let blockedTokens = [
            "rm -rf", "sudo", "shutdown", "reboot", "mkfs", "dd ", ">:",
            "vi ", "nano", "top", "htop", "less", "more", "ssh "
        ]
        if blockedTokens.contains(where: { lower.contains($0) }) {
            return false
        }
        return true
    }

    static func runShell(_ command: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (1, "无法启动命令: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func extractCommandByToken(_ text: String, token: String) -> String? {
        guard let range = text.range(of: token) else { return nil }
        let tail = text[range.upperBound...]
        let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        let command = line.map(String.init) ?? String(tail)
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractCommandWithoutTag(from text: String) -> String? {
        let candidates = ["ls", "zip", "tar", "cp", "mv", "cat", "pwd", "mkdir", "rmdir"]
        let lines = text.split(separator: "\n")
        for line in lines {
            let raw = String(line)
            for cmd in candidates {
                if let range = raw.range(of: "\(cmd) ") ?? (raw.hasPrefix("\(cmd)\t") ? raw.range(of: cmd) : nil) {
                    let tail = raw[range.lowerBound...]
                    let cleaned = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.count > 1 {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }
}
