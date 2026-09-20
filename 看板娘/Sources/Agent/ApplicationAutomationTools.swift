//
//  ApplicationAutomationTools.swift
//  看板娘
//
//  Explicit, reviewable bridges to Shortcuts, AppleScript and Accessibility.
//

import AppKit
import ApplicationServices
import Foundation

private struct AutomationProcessResult {
    let status: Int32
    let output: String
}

private enum AutomationProcess {
    static func run(_ executable: String, _ arguments: [String]) -> AutomationProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return AutomationProcessResult(status: 1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return AutomationProcessResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
}

@MainActor
final class ListShortcutsTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "list_shortcuts",
        description: "列出用户在 macOS 快捷指令中可用的快捷指令名称。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "列出快捷指令" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AutomationProcess.run("/usr/bin/shortcuts", ["list"])
            Task { @MainActor in completion(result.status == 0 ? .success(result.output) : .failure(result.output)) }
        }
    }
}

@MainActor
final class RunShortcutTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "run_shortcut",
        description: "运行一个已安装的 macOS 快捷指令。可传入文本或文件作为输入；执行前需要用户确认。",
        parameters: [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "快捷指令的精确名称"],
                "input_path": ["type": "string", "description": "可选输入文件绝对路径"]
            ],
            "required": ["name"], "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String { "运行快捷指令“\(arguments["name"] as? String ?? "")”" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let name = arguments["name"] as? String, !name.isEmpty else { completion(.failure("缺少 name")); return }
        var args = ["run", name]
        if let path = arguments["input_path"] as? String, !path.isEmpty {
            guard AgentFileAccessStore.shared.canRead(path) else { completion(.failure(AgentFileAccessStore.denialMessage(path: path))); return }
            args += ["--input-path", path]
        }
        let executionArguments = args
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AutomationProcess.run("/usr/bin/shortcuts", executionArguments)
            Task { @MainActor in completion(result.status == 0 ? .success(result.output.isEmpty ? "快捷指令已完成" : result.output) : .failure(result.output)) }
        }
    }
}

@MainActor
final class RunAppleScriptTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "run_applescript",
        description: "执行 AppleScript 以操作脚本化的 macOS 应用。执行前始终展示完整脚本并需要用户确认。",
        parameters: [
            "type": "object",
            "properties": ["script": ["type": "string", "description": "完整 AppleScript 源码"]],
            "required": ["script"], "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String { "执行 AppleScript：\n\n\(arguments["script"] as? String ?? "")" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let script = arguments["script"] as? String, !script.isEmpty else { completion(.failure("缺少 script")); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AutomationProcess.run("/usr/bin/osascript", ["-e", script])
            Task { @MainActor in completion(result.status == 0 ? .success(result.output.isEmpty ? "AppleScript 已完成" : result.output) : .failure(result.output)) }
        }
    }
}

@MainActor
final class ControlApplicationTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "control_application",
        description: "通过 macOS 辅助功能激活应用、点击菜单项或输入键盘文本。这类界面操作执行前需要用户确认。",
        parameters: [
            "type": "object",
            "properties": [
                "application": ["type": "string", "description": "应用名称"],
                "action": ["type": "string", "enum": ["activate", "click_menu", "keystroke"]],
                "menu": ["type": "string", "description": "click_menu 的菜单名"],
                "menu_item": ["type": "string", "description": "click_menu 的菜单项"],
                "text": ["type": "string", "description": "keystroke 的文本"]
            ],
            "required": ["application", "action"], "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        "在 \(arguments["application"] as? String ?? "") 中执行 \(arguments["action"] as? String ?? "")"
    }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(.failure("当前进程尚未获得设备控制权限。请在看板娘 → 偏好设置 → 安全与隐私中授权，然后完全退出并重新打开看板娘。"))
            return
        }
        guard let app = arguments["application"] as? String,
              let action = arguments["action"] as? String else { completion(.failure("缺少应用或操作")); return }
        let q: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let script: String
        switch action {
        case "activate":
            script = "tell application \(q(app)) to activate"
        case "click_menu":
            guard let menu = arguments["menu"] as? String, let item = arguments["menu_item"] as? String else { completion(.failure("缺少 menu 或 menu_item")); return }
            script = "tell application \(q(app)) to activate\ntell application \"System Events\" to tell process \(q(app)) to click menu item \(q(item)) of menu \(q(menu)) of menu bar 1"
        case "keystroke":
            guard let text = arguments["text"] as? String else { completion(.failure("缺少 text")); return }
            script = "tell application \(q(app)) to activate\ntell application \"System Events\" to keystroke \(q(text))"
        default:
            completion(.failure("不支持的 action")); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AutomationProcess.run("/usr/bin/osascript", ["-e", script])
            Task { @MainActor in completion(result.status == 0 ? .success("操作已完成") : .failure(result.output)) }
        }
    }
}

@MainActor
final class PresentActionPlanTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "present_action_plan",
        description: "在对多个文件或外部应用做变更前，向用户展示操作计划和受影响路径并等待确认。",
        parameters: [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "steps": ["type": "array", "items": ["type": "string"]],
                "affected_paths": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["title", "steps"], "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        let title = arguments["title"] as? String ?? "操作计划"
        let steps = arguments["steps"] as? [String] ?? []
        let paths = arguments["affected_paths"] as? [String] ?? []
        return ([title] + steps.enumerated().map { "\($0.offset + 1). \($0.element)" } + (paths.isEmpty ? [] : ["受影响路径：", paths.joined(separator: "\n")])).joined(separator: "\n")
    }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        completion(.success("用户已批准计划，可按步骤继续。"))
    }
}

@MainActor
final class UndoLastFileOperationTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "undo_last_file_operation",
        description: "撤销 Agent 最近一次可撤销的文件写入、复制或移动。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String { AgentFileUndoStore.shared.latest.map { "撤销：\($0.summary)" } ?? "撤销最近文件操作" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        switch AgentFileUndoStore.shared.undoLatest() {
        case .success(let message): completion(.success(message))
        case .failure(let error): completion(.failure(error.localizedDescription))
        }
    }
}
