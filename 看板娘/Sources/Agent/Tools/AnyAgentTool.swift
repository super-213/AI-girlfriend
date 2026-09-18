import Foundation

struct AnyAgentTool<Context: Sendable>: Sendable {
    let definition: ToolDefinition
    let behavior: ToolBehavior
    private let invokeValue: @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput
    private let requiresApprovalValue: @Sendable (String) async throws -> Bool
    private let approvalSummaryValue: @Sendable (String) async -> String

    init<T: AgentTool>(_ tool: T) where T.Context == Context {
        definition = T.definition
        behavior = T.behavior
        requiresApprovalValue = { _ in T.behavior.requiresApproval }
        approvalSummaryValue = { _ in "执行工具 \(T.definition.name)" }
        invokeValue = { context, rawArguments in
            guard let data = rawArguments.data(using: .utf8) else {
                throw AgentError.invalidToolArguments(
                    toolName: T.definition.name,
                    detail: "参数不是 UTF-8 文本"
                )
            }
            let arguments: T.Arguments
            do {
                arguments = try JSONDecoder().decode(T.Arguments.self, from: data)
            } catch {
                throw AgentError.invalidToolArguments(
                    toolName: T.definition.name,
                    detail: error.localizedDescription
                )
            }
            let output = try await tool.invoke(context: context, arguments: arguments)
            let encoded = try JSONEncoder().encode(output)
            let content = String(data: encoded, encoding: .utf8) ?? "null"
            return ToolInvocationOutput(content: content)
        }
    }

    init(
        definition: ToolDefinition,
        behavior: ToolBehavior = .readOnly,
        requiresApproval: @escaping @Sendable (String) async throws -> Bool = { _ in false },
        approvalSummary: @escaping @Sendable (String) async -> String = { _ in "" },
        invoke: @escaping @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput
    ) {
        self.definition = definition
        self.behavior = behavior
        requiresApprovalValue = requiresApproval
        approvalSummaryValue = approvalSummary
        invokeValue = invoke
    }

    func invoke(context: ToolContext<Context>, arguments: String) async throws -> ToolInvocationOutput {
        try await invokeValue(context, arguments)
    }

    func requiresApproval(arguments: String) async throws -> Bool {
        if behavior.requiresApproval { return true }
        return try await requiresApprovalValue(arguments)
    }

    func approvalSummary(arguments: String) async -> String {
        let summary = await approvalSummaryValue(arguments)
        return summary.isEmpty ? "执行工具 \(definition.name)" : summary
    }
}
