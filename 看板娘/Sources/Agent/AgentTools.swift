//
//  AgentTools.swift
//  看板娘
//
//  Extensible tool protocol, registry, and built-in local tools.
//

import Foundation

enum AgentRuntimeToolName {
    static let compactContext = "compact_context"
}

@MainActor
protocol AgentTool: AnyObject {
    var definition: AgentToolDefinition { get }
    var requiresConfirmation: Bool { get }
    func requiresConfirmation(arguments: [String: Any]) -> Bool
    func approvalSummary(arguments: [String: Any]) -> String
    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    )
}

extension AgentTool {
    func requiresConfirmation(arguments: [String: Any]) -> Bool {
        requiresConfirmation
    }
}

@MainActor
final class AgentToolRegistry {
    private var toolsByName: [String: any AgentTool] = [:]

    var definitions: [AgentToolDefinition] {
        toolsByName.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func register(_ tool: any AgentTool) {
        toolsByName[tool.definition.name] = tool
    }

    func tool(named name: String) -> (any AgentTool)? {
        toolsByName[name]
    }

    static func standard() -> AgentToolRegistry {
        let registry = AgentToolRegistry()
        registry.register(CurrentDateTimeTool())
        registry.register(CompactContextTool())
        registry.register(ReadSkillTool())
        registry.register(ListKnowledgeBasesTool())
        registry.register(AddToKnowledgeBaseTool())
        registry.register(SearchKnowledgeBaseTool())
        registry.register(ListDirectoryTool())
        registry.register(ReadFileTool())
        registry.register(ReadDocumentTool())
        registry.register(GetFileInfoTool())
        registry.register(SearchFilesTool())
        registry.register(OpenFileTool())
        registry.register(RevealInFinderTool())
        registry.register(OpenApplicationTool())
        registry.register(WriteTextFileTool())
        registry.register(CopyFileTool())
        registry.register(MoveFileTool())
        registry.register(WriteDocumentTool())
        registry.register(ListShortcutsTool())
        registry.register(RunShortcutTool())
        registry.register(RunAppleScriptTool())
        registry.register(ControlApplicationTool())
        registry.register(ObserveDesktopTool())
        registry.register(PerformUIActionTool())
        registry.register(PresentActionPlanTool())
        registry.register(UndoLastFileOperationTool())
        registry.register(RunCommandTool())
        registry.register(ListCharactersTool())
        registry.register(SwitchCharacterTool())
        registry.register(ListAutomationsTool())
        registry.register(RunAutomationTool())
        registry.register(GetCodexTaskStatusTool())
        return registry
    }
}

@MainActor
final class CompactContextTool: AgentTool {
    let definition = AgentToolDefinition(
        name: AgentRuntimeToolName.compactContext,
        description: "主动压缩当前会话上下文。当用户明确要求压缩、整理或缩短当前上下文时调用。Runtime 会保留最新完整轮次，并将更早的对话和工具结果整理为结构化摘要。",
        parameters: [
            "type": "object",
            "properties": [:],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "压缩当前会话上下文"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        completion(.success("已请求压缩当前会话上下文；Runtime 将保留最新完整轮次，并摘要更早内容。"))
    }
}

@MainActor
final class ReadSkillTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "read_skill",
        description: "按可用 Skills 目录中的 name 读取已启用 Skill 的完整 SKILL.md 指令。当用户任务匹配某项 Skill 时调用。",
        parameters: [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Skills 目录中的精确技能名称"]
            ],
            "required": ["name"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func approvalSummary(arguments: [String: Any]) -> String {
        "读取 Skill：\(arguments["name"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let rawName = arguments["name"] as? String else {
            completion(.failure("缺少 name"))
            return
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.caseInsensitiveCompare(KnowledgeBaseAnswerSkill.name) == .orderedSame,
           KnowledgeBaseRegistry.shared.hasEnabledKnowledgeBase {
            completion(.success(KnowledgeBaseAnswerSkill.content))
            return
        }
        guard let skill = SkillLibrary.enabledSkill(named: name, defaults: defaults) else {
            completion(.failure("未找到已启用且有效的 Skill：\(name)"))
            return
        }
        do {
            let content = try String(contentsOfFile: skill.path, encoding: .utf8)
            let contextualized = """
            Skill 资源根目录：\(skill.resourceBasePath)
            请以该目录为基准解析 SKILL.md 中的 scripts/、references/ 和 assets/ 相对路径。

            \(content)
            """
            completion(.success(contextualized))
        } catch {
            completion(.failure("读取 Skill 失败：\(error.localizedDescription)"))
        }
    }
}

@MainActor
private final class CurrentDateTimeTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "get_current_datetime",
        description: "读取用户 Mac 当前准确的本地日期、时间、星期和时区。凡是涉及今天、现在、日期、时间或星期的问题都应调用此工具。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String { "读取当前日期和时间" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss EEEE"
        let value = [
            "local_datetime": formatter.string(from: Date()),
            "timezone": TimeZone.current.identifier,
            "utc_offset_seconds": TimeZone.current.secondsFromGMT()
        ] as [String: Any]
        completion(.success(Self.jsonString(value)))
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return String(describing: object)
        }
        return String(data: data, encoding: .utf8) ?? String(describing: object)
    }
}

@MainActor
private final class ListDirectoryTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "list_directory",
        description: "列出本地目录内容。路径必须是绝对路径；省略时使用应用当前工作目录。",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "要列出的绝对目录路径"]
            ],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "列出目录 \(arguments["path"] as? String ?? FileManager.default.currentDirectoryPath)"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let path = (arguments["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = path.flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.currentDirectoryPath
        guard AgentFileAccessStore.shared.canRead(resolvedPath) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: resolvedPath)))
            return
        }
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: resolvedPath).sorted()
            let limited = Array(entries.prefix(500))
            let suffix = entries.count > limited.count ? "\n…其余 \(entries.count - limited.count) 项已省略" : ""
            completion(.success(limited.joined(separator: "\n") + suffix))
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}

@MainActor
private final class ReadFileTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "read_file",
        description: "读取 UTF-8 文本文件。路径必须是绝对路径；单次最多返回 100000 个字符。",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "文件的绝对路径"]
            ],
            "required": ["path"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "读取文件 \(arguments["path"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            completion(.failure("缺少 path"))
            return
        }
        guard AgentFileAccessStore.shared.canRead(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: path)))
            return
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let limit = 100_000
            let result = content.count > limit
                ? String(content.prefix(limit)) + "\n…文件内容已截断"
                : content
            completion(.success(result))
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}

@MainActor
private final class RunCommandTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "run_command",
        description: "在本机通过 /bin/zsh -lc 执行一条非交互式命令。是否需要确认由用户的命令权限设置决定。",
        parameters: [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "要执行的单条 shell 命令"],
                "working_directory": ["type": "string", "description": "可选的绝对工作目录；项目会话中使用当前项目根目录"]
            ],
            "required": ["command"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func requiresConfirmation(arguments: [String: Any]) -> Bool {
        guard let command = arguments["command"] as? String else { return false }
        return CommandExecutionSupport.permissionDecision(for: command) == .requireApproval
    }

    func approvalSummary(arguments: [String: Any]) -> String {
        arguments["command"] as? String ?? "执行 Shell 命令"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let command = arguments["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure("缺少 command"))
            return
        }
        if case .deny(let matchedRule) = CommandExecutionSupport.permissionDecision(for: command) {
            completion(.failure("命令被黑名单规则“\(matchedRule)”阻止"))
            return
        }

        let workingDirectory = (arguments["working_directory"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let workingDirectory, !workingDirectory.isEmpty {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: workingDirectory,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                completion(.failure("工作目录不存在：\(workingDirectory)"))
                return
            }
            guard AgentFileAccessStore.shared.canRead(workingDirectory) else {
                completion(.failure(AgentFileAccessStore.denialMessage(path: workingDirectory)))
                return
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let (exitCode, output) = CommandExecutionSupport.runShell(
                command,
                workingDirectory: workingDirectory
            )
            let result = "退出码: \(exitCode)\n输出:\n\(output.isEmpty ? "(无输出)" : output)"
            Task { @MainActor in
                completion(exitCode == 0 ? .success(result) : .failure(result))
            }
        }
    }
}

@MainActor
private final class ListCharactersTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "list_pet_characters",
        description: "列出桌宠应用当前可切换的全部角色。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "列出桌宠角色" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let characters = PetControlService.shared.listCharacters(
            context: PetControlRequestContext(source: .ui, actorID: "dialog-agent")
        )
        completion(.success(Self.encode(characters)))
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

@MainActor
private final class SwitchCharacterTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "switch_pet_character",
        description: "按角色名称、ID 或序号切换当前桌宠角色。此操作会改变应用状态。",
        parameters: [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "角色名称或 ID"],
                "index": ["type": "integer", "description": "角色序号"]
            ],
            "additionalProperties": false,
            "anyOf": [["required": ["name"]], ["required": ["index"]]]
        ]
    )
    let requiresConfirmation = true

    func approvalSummary(arguments: [String: Any]) -> String {
        if let name = arguments["name"] as? String { return "切换桌宠角色为 \(name)" }
        return "切换桌宠角色为序号 \(arguments["index"] ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let request = SwitchCharacterRequest(
            index: arguments["index"] as? Int,
            name: arguments["name"] as? String,
            context: PetControlRequestContext(source: .ui, actorID: "dialog-agent")
        )
        do {
            let result = try PetControlService.shared.switchCharacter(request)
            completion(.success("已切换为 \(result.name)"))
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}

@MainActor
private final class ListAutomationsTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "list_automations",
        description: "列出桌宠应用中已有的自动化任务及其 ID、启用状态和下次运行时间。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "列出自动化任务" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let items = PetControlService.shared.listAutomations(
            context: PetControlRequestContext(source: .ui, actorID: "dialog-agent")
        )
        guard let data = try? JSONEncoder().encode(items) else {
            completion(.failure("自动化数据编码失败"))
            return
        }
        completion(.success(String(data: data, encoding: .utf8) ?? "[]"))
    }
}

@MainActor
private final class RunAutomationTool: AgentTool {
    let definition = AgentToolDefinition(
        name: "run_automation",
        description: "执行指定 ID 的已有自动化任务。此操作会改变应用状态，执行前必须由用户确认。",
        parameters: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "自动化任务 UUID"]
            ],
            "required": ["id"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = true

    func approvalSummary(arguments: [String: Any]) -> String {
        "运行自动化 \(arguments["id"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let rawID = arguments["id"] as? String, let id = UUID(uuidString: rawID) else {
            completion(.failure("id 不是有效 UUID"))
            return
        }
        do {
            let result = try PetControlService.shared.runAutomation(
                RunAutomationRequest(
                    id: id,
                    context: PetControlRequestContext(source: .ui, actorID: "dialog-agent")
                )
            )
            completion(.success("自动化已接受，requestID: \(result.requestID.uuidString)"))
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}
