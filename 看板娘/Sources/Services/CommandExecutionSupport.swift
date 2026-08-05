//
//  CommandExecutionSupport.swift
//  看板娘
//
//  Agent Shell 工具的命令校验与执行支持
//

import Foundation

enum CommandExecutionSupport {
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

}
