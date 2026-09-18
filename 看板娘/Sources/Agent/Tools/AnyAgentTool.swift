import Foundation

struct AnyAgentTool<Context: Sendable>: Sendable {
    let definition: ToolDefinition
    let behavior: ToolBehavior
    private let invokeValue: @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput

    init<T: AgentTool>(_ tool: T) where T.Context == Context {
        definition = T.definition
        behavior = T.behavior
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
        invoke: @escaping @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput
    ) {
        self.definition = definition
        self.behavior = behavior
        invokeValue = invoke
    }

    func invoke(context: ToolContext<Context>, arguments: String) async throws -> ToolInvocationOutput {
        try await invokeValue(context, arguments)
    }
}
