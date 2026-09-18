import Foundation

/// Enforces the app's file and command policies independently of model prompting.
struct AppAgentToolGuardrail: ToolGuardrail {
    typealias Context = AppAgentContext
    let name = "app_tool_permission"

    private static let readPathKeys = ["path", "working_directory", "directory", "input_path"]
    private static let writeToolNames: Set<String> = [
        "write_text_file", "write_document", "copy_file", "move_file", "save_file"
    ]
    private static let writePathKeys = ["path", "destination"]

    func evaluateInput(
        context: AgentGuardrailContext<AppAgentContext>,
        call: ToolCallItem,
        tool: ToolDefinition
    ) async throws -> GuardrailResult {
        guard let data = call.arguments.data(using: .utf8),
              let arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return GuardrailResult(action: .stop, message: "工具参数不是有效 JSON 对象")
        }

        if call.name == "run_command" {
            guard let command = arguments["command"] as? String,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return GuardrailResult(action: .stop, message: "Shell 命令不能为空")
            }
            switch context.context.commandPermissionPolicy.decision(for: command) {
            case .allow:
                break
            case .requireApproval:
                return GuardrailResult(action: .requireApproval, message: "执行 Shell 命令：\(command)")
            case .deny(let rule):
                return GuardrailResult(action: .stop, message: "命令命中黑名单规则：\(rule)")
            }
        }

        let policy = context.context.fileAccessPolicy
        var readPathKeys = Self.readPathKeys
        if ["copy_file", "move_file"].contains(call.name) {
            readPathKeys.append("source")
        }
        for key in readPathKeys {
            if let path = arguments[key] as? String,
               !path.isEmpty,
               !policy.canRead(path) {
                return GuardrailResult(action: .stop, message: Self.denialMessage(path))
            }
        }
        if let paths = arguments["paths"] as? [String],
           let denied = paths.first(where: { !policy.canRead($0) }) {
            return GuardrailResult(action: .stop, message: Self.denialMessage(denied))
        }

        let isUISave = call.name == "perform_ui_action"
            && arguments["action"] as? String == "save_file"
        if Self.writeToolNames.contains(call.name) || isUISave {
            for key in Self.writePathKeys {
                if let path = arguments[key] as? String,
                   !path.isEmpty,
                   !policy.canWrite(path) {
                    return GuardrailResult(action: .stop, message: Self.denialMessage(path))
                }
            }
        }
        return .allowed
    }

    private static func denialMessage(_ path: String) -> String {
        "路径尚未授权：\(path)。请将文件拖给角色，或在偏好设置中添加允许的目录。"
    }

    func evaluateOutput(
        context: AgentGuardrailContext<AppAgentContext>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult {
        guard SensitiveDataRedactor.redact(result.content) != result.content else { return .allowed }
        return GuardrailResult(
            action: .stop,
            message: "工具结果包含疑似凭据，已阻止继续传递"
        )
    }
}

struct AppAgentOutputGuardrail: OutputGuardrail {
    typealias Context = AppAgentContext
    typealias Output = String
    let name = "app_output_safety"

    func evaluate(
        context: AgentGuardrailContext<AppAgentContext>,
        output: String
    ) async throws -> GuardrailResult {
        guard SensitiveDataRedactor.redact(output) != output else { return .allowed }
        return GuardrailResult(action: .stop, message: "模型输出包含疑似凭据，已阻止展示")
    }
}
