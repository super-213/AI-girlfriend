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
            ),
            requiresApproval: { rawArguments in
                try await box.requiresApproval(rawArguments: rawArguments)
            },
            approvalSummary: { rawArguments in
                await box.approvalSummary(rawArguments: rawArguments)
            }
        ) { _, rawArguments in
            try await box.invoke(rawArguments: rawArguments)
        }
    }

    /// Keeps the existing business implementation while making Codable
    /// arguments the mandatory boundary presented to AgentRunner.
    @MainActor
    static func erase<Arguments: Codable & Sendable>(
        _ tool: any LegacyAgentTool,
        arguments: Arguments.Type,
        behavior: ToolBehavior? = nil
    ) -> AnyAgentTool<Context> {
        let definition = ToolDefinition(
            name: tool.definition.name,
            description: tool.definition.description,
            parameters: (try? JSONValue(any: tool.definition.parameters)) ?? .object([:])
        )
        let box = LegacyToolBox(tool)
        let resolvedBehavior = behavior ?? ToolBehavior(
            isReadOnly: !tool.requiresConfirmation,
            isIdempotent: !tool.requiresConfirmation,
            hasExternalSideEffects: tool.requiresConfirmation,
            requiresApproval: tool.requiresConfirmation,
            allowsParallelExecution: false,
            defaultTimeout: nil,
            allowsAutomaticRetry: false,
            riskLevel: tool.requiresConfirmation ? .high : .low
        )
        return AnyAgentTool(
            definition: definition,
            behavior: resolvedBehavior,
            argumentBoundary: .codable,
            requiresApproval: { rawArguments in
                let canonical = try Self.canonicalArguments(
                    rawArguments,
                    as: Arguments.self,
                    toolName: definition.name
                )
                return try await box.requiresApproval(rawArguments: canonical)
            },
            approvalSummary: { rawArguments in
                guard let canonical = try? Self.canonicalArguments(
                    rawArguments,
                    as: Arguments.self,
                    toolName: definition.name
                ) else { return "执行工具 \(definition.name)" }
                return await box.approvalSummary(rawArguments: canonical)
            },
            invoke: { _, rawArguments in
                let canonical = try Self.canonicalArguments(
                    rawArguments,
                    as: Arguments.self,
                    toolName: definition.name
                )
                return try await box.invoke(rawArguments: canonical)
            }
        )
    }

    private static func canonicalArguments<Arguments: Codable & Sendable>(
        _ rawArguments: String,
        as type: Arguments.Type,
        toolName: String
    ) throws -> String {
        guard let data = rawArguments.data(using: .utf8) else {
            throw AgentError.invalidToolArguments(toolName: toolName, detail: "参数不是 UTF-8 文本")
        }
        let value: Arguments
        do {
            value = try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentError.invalidToolArguments(toolName: toolName, detail: error.localizedDescription)
        }
        do {
            let encoded = try JSONEncoder().encode(value)
            guard let canonical = String(data: encoded, encoding: .utf8) else {
                throw AgentError.invalidToolArguments(toolName: toolName, detail: "参数无法编码为 UTF-8")
            }
            return canonical
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.invalidToolArguments(toolName: toolName, detail: error.localizedDescription)
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
        let bridge = LegacyInvocationBridge()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                bridge.install(continuation)
                Task { @MainActor [tool] in
                    guard !bridge.isCancelled else { return }
                    guard let data = rawArguments.data(using: .utf8),
                          let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        bridge.resume(throwing: AgentError.invalidToolArguments(
                            toolName: tool.definition.name,
                            detail: "参数不是 JSON 对象"
                        ))
                        return
                    }
                    tool.execute(arguments: arguments) { result in
                        if result.isError {
                            bridge.resume(throwing: AgentError.toolExecutionFailed(
                                toolName: tool.definition.name,
                                detail: result.content
                            ))
                        } else {
                            bridge.resume(returning: ToolInvocationOutput(
                                content: result.modelContent,
                                imagePaths: result.imagePaths
                            ))
                        }
                    }
                }
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    func requiresApproval(rawArguments: String) async throws -> Bool {
        try await MainActor.run {
            let arguments = try Self.arguments(from: rawArguments, toolName: tool.definition.name)
            return tool.requiresConfirmation(arguments: arguments)
        }
    }

    func approvalSummary(rawArguments: String) async -> String {
        await MainActor.run {
            guard let arguments = try? Self.arguments(
                from: rawArguments,
                toolName: tool.definition.name
            ) else { return "执行工具 \(tool.definition.name)" }
            return tool.approvalSummary(arguments: arguments)
        }
    }

    @MainActor
    private static func arguments(from rawArguments: String, toolName: String) throws -> [String: Any] {
        guard let data = rawArguments.data(using: .utf8),
              let arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.invalidToolArguments(toolName: toolName, detail: "参数不是 JSON 对象")
        }
        return arguments
    }
}

private final class LegacyInvocationBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ToolInvocationOutput, Error>?
    private var completed = false
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ continuation: CheckedContinuation<ToolInvocationOutput, Error>) {
        let shouldCancel = lock.withLock { () -> Bool in
            if completed { return true }
            self.continuation = continuation
            return cancelled
        }
        if shouldCancel { cancel() }
    }

    func resume(returning output: ToolInvocationOutput) {
        finish(.success(output))
    }

    func resume(throwing error: Error) {
        finish(.failure(error))
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<ToolInvocationOutput, Error>? in
            cancelled = true
            guard !completed, let continuation else { return nil }
            completed = true
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: AgentError.cancelled)
    }

    private func finish(_ result: Result<ToolInvocationOutput, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<ToolInvocationOutput, Error>? in
            guard !completed, let continuation else { return nil }
            completed = true
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
