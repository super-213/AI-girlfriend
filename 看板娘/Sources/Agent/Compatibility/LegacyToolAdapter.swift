import Foundation

/// Adapts existing callback-based tools while they are migrated one by one.
struct LegacyToolAdapter<Context: Sendable>: Sendable {
    @MainActor
    static func erase(_ tool: any LegacyAgentTool) -> AnyAgentTool<Context> {
        let definition = ToolDefinition(
            name: tool.definition.name,
            description: tool.definition.description,
            parameters: (try? JSONValue(any: tool.definition.parameters)) ?? .object([:])
        )
        let box = LegacyToolBox(tool)
        return AnyAgentTool(
            definition: definition,
            behavior: ToolBehavior(
                isReadOnly: !tool.requiresConfirmation,
                isIdempotent: !tool.requiresConfirmation,
                hasExternalSideEffects: tool.requiresConfirmation,
                requiresApproval: tool.requiresConfirmation,
                allowsParallelExecution: false,
                defaultTimeout: nil,
                allowsAutomaticRetry: false,
                riskLevel: tool.requiresConfirmation ? .high : .low
            )
        ) { _, rawArguments in
            try await box.invoke(rawArguments: rawArguments)
        }
    }
}

private final class LegacyToolBox: @unchecked Sendable {
    private let tool: any LegacyAgentTool

    @MainActor
    init(_ tool: any LegacyAgentTool) {
        self.tool = tool
    }

    func invoke(rawArguments: String) async throws -> ToolInvocationOutput {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor [tool] in
                guard let data = rawArguments.data(using: .utf8),
                      let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(throwing: AgentError.invalidToolArguments(
                        toolName: tool.definition.name,
                        detail: "参数不是 JSON 对象"
                    ))
                    return
                }
                tool.execute(arguments: arguments) { result in
                    if result.isError {
                        continuation.resume(throwing: AgentError.toolExecutionFailed(
                            toolName: tool.definition.name,
                            detail: result.content
                        ))
                    } else {
                        continuation.resume(returning: ToolInvocationOutput(
                            content: result.modelContent,
                            imagePaths: result.imagePaths
                        ))
                    }
                }
            }
        }
    }
}
