//
//  CommandExecutionSupport.swift
//  看板娘
//
//  Agent Shell 工具的命令校验与执行支持
//

import Foundation

enum CommandExecutionSupport {
    static func permissionDecision(for command: String) -> CommandPermissionDecision {
        CommandPermissionPolicy().decision(for: command)
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

        // 先持续排空管道，再等待退出，避免大量输出填满管道后子进程死锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

}
