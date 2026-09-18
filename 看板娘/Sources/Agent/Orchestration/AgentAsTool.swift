import Foundation

struct AgentAsToolArguments: Codable, Equatable, Sendable {
    let input: String
}

struct AgentAsToolResult: Codable, Equatable, Sendable {
    let agentID: String
    let output: String
    let usage: AgentUsage
}

enum AgentAsTool {
    static func make<Context: Sendable>(
        name: String,
        description: String,
        agent: AgentDefinition<Context, String>,
        runner: AgentRunner,
        configuration: RunConfiguration = RunConfiguration(),
        behavior: ToolBehavior = .readOnly,
        inputTransform: @escaping @Sendable (String) -> String = { $0 }
    ) -> AnyAgentTool<Context> {
        make(
            name: name,
            description: description,
            agent: agent,
            runner: runner,
            contextTransform: { $0.context },
            configuration: configuration,
            behavior: behavior,
            inputTransform: inputTransform
        )
    }

    static func make<ParentContext: Sendable, ExpertContext: Sendable>(
        name: String,
        description: String,
        agent: AgentDefinition<ExpertContext, String>,
        runner: AgentRunner,
        contextTransform: @escaping @Sendable (ToolContext<ParentContext>) -> ExpertContext,
        configuration: RunConfiguration = RunConfiguration(),
        behavior: ToolBehavior = .readOnly,
        inputTransform: @escaping @Sendable (String) -> String = { $0 }
    ) -> AnyAgentTool<ParentContext> {
        AnyAgentTool(
            definition: ToolDefinition(
                name: name,
                description: description,
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "input": .object([
                            "type": .string("string"),
                            "description": .string("交给专家 Agent 的边界明确任务")
                        ])
                    ]),
                    "required": .array([.string("input")]),
                    "additionalProperties": .bool(false)
                ])
            ),
            behavior: behavior,
            invoke: { context, rawArguments in
                guard let data = rawArguments.data(using: .utf8) else {
                    throw AgentError.invalidToolArguments(toolName: name, detail: "参数不是 UTF-8 文本")
                }
                let arguments: AgentAsToolArguments
                do {
                    arguments = try JSONDecoder().decode(AgentAsToolArguments.self, from: data)
                } catch {
                    throw AgentError.invalidToolArguments(
                        toolName: name,
                        detail: error.localizedDescription
                    )
                }
                let session = MemoryAgentSession(id: "agent-tool-\(UUID().uuidString)")
                let result = try await runner.runNested(
                    agent: agent,
                    input: AgentInput(inputTransform(arguments.input)),
                    context: contextTransform(context),
                    session: session,
                    configuration: configuration,
                    parentTrace: context.traceContext
                ).result.value
                guard let output = result.finalOutput else {
                    throw AgentError.toolExecutionFailed(
                        toolName: name,
                        detail: "专家 Agent 在完成前被中断"
                    )
                }
                let payload = AgentAsToolResult(
                    agentID: result.lastAgentID,
                    output: output,
                    usage: result.usage
                )
                let encoded = try JSONEncoder().encode(payload)
                return ToolInvocationOutput(
                    content: String(data: encoded, encoding: .utf8) ?? "{}"
                )
            }
        )
    }
}
