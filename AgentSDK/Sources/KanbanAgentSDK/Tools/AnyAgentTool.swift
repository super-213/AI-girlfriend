import Foundation

public enum ToolArgumentBoundary: Equatable, Sendable {
    case codable
    case rawJSON
}

public struct AnyAgentTool<Context: Sendable>: Sendable {
    public let definition: ToolDefinition
    public let behavior: ToolBehavior
    public let argumentBoundary: ToolArgumentBoundary
    private let invokeValue: @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput
    private let requiresApprovalValue: @Sendable (String) async throws -> Bool
    private let approvalSummaryValue: @Sendable (String) async -> String

    init<T: AgentTool>(_ tool: T) where T.Context == Context {
        definition = T.definition
        behavior = T.behavior
        argumentBoundary = .codable
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

    public init(
        definition: ToolDefinition,
        behavior: ToolBehavior = .readOnly,
        argumentBoundary: ToolArgumentBoundary = .rawJSON,
        requiresApproval: @escaping @Sendable (String) async throws -> Bool = { _ in false },
        approvalSummary: @escaping @Sendable (String) async -> String = { _ in "" },
        invoke: @escaping @Sendable (ToolContext<Context>, String) async throws -> ToolInvocationOutput
    ) {
        self.definition = definition
        self.behavior = behavior
        self.argumentBoundary = argumentBoundary
        requiresApprovalValue = requiresApproval
        approvalSummaryValue = approvalSummary
        invokeValue = invoke
    }

    public func invoke(context: ToolContext<Context>, arguments: String) async throws -> ToolInvocationOutput {
        try ToolArgumentValidator.validate(arguments, definition: definition)
        return try await invokeValue(context, arguments)
    }

    public func requiresApproval(arguments: String) async throws -> Bool {
        if behavior.requiresApproval { return true }
        return try await requiresApprovalValue(arguments)
    }

    public func approvalSummary(arguments: String) async -> String {
        let summary = await approvalSummaryValue(arguments)
        return summary.isEmpty ? "执行工具 \(definition.name)" : summary
    }
}
