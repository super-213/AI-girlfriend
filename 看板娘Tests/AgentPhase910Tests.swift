import Foundation
import Testing
@testable import 看板娘

struct AgentPhase910Tests {
    private final class FakeProvider: AgentModelProvider, @unchecked Sendable {
        let id = "phase-910-fake"
        let capabilities = ModelCapabilities(
            supportsTools: true,
            supportsParallelTools: true,
            supportsStructuredOutput: true,
            supportsImageInput: true,
            supportsServerManagedState: false,
            supportsPromptCaching: false,
            supportsResponsesAPI: false
        )
        private let lock = NSLock()
        private var responses: [ModelResponse]
        private var recorded: [ModelRequest] = []

        init(_ responses: [ModelResponse]) { self.responses = responses }

        func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
            let response = lock.withLock {
                recorded.append(request)
                return responses.removeFirst()
            }
            return AsyncThrowingStream { continuation in
                if !response.content.isEmpty { continuation.yield(.textDelta(response.content)) }
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }

        var requests: [ModelRequest] { lock.withLock { recorded } }
    }

    private struct ValueArguments: Codable, Sendable { let value: String }
    private struct ValueOutput: Codable, Sendable { let value: String }

    private struct EchoTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput

        static let definition = ToolDefinition(
            name: "echo_secret",
            description: "Echo a value",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")])
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false)
            ])
        )

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            ValueOutput(value: arguments.value)
        }
    }

    private struct RiskyTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput
        static let definition = ToolDefinition(name: "risky_trace", description: "Risky")
        static let behavior = ToolBehavior.mutating

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            ValueOutput(value: arguments.value)
        }
    }

    private struct AllowInputGuardrail: InputGuardrail {
        let name = "trace_input"
        func evaluate(
            context: AgentGuardrailContext<Void>,
            input: AgentInput
        ) async throws -> GuardrailResult { .allowed }
    }

    private struct AllowToolGuardrail: ToolGuardrail {
        let name = "trace_tool"
        func evaluateInput(
            context: AgentGuardrailContext<Void>,
            call: ToolCallItem,
            tool: ToolDefinition
        ) async throws -> GuardrailResult { .allowed }
    }

    private struct BlockToolGuardrail: ToolGuardrail {
        let name = "block_mcp"
        func evaluateInput(
            context: AgentGuardrailContext<Void>,
            call: ToolCallItem,
            tool: ToolDefinition
        ) async throws -> GuardrailResult {
            GuardrailResult(action: .stop, message: "MCP blocked")
        }
    }

    private actor FakeMCPClient: MCPToolClient {
        let descriptors: [MCPToolDescriptor]
        private(set) var calls: [(String, JSONValue)] = []

        init(descriptors: [MCPToolDescriptor]) { self.descriptors = descriptors }

        func listTools(server: MCPServerConfiguration) async throws -> [MCPToolDescriptor] {
            descriptors
        }

        func callTool(
            server: MCPServerConfiguration,
            name: String,
            arguments: JSONValue
        ) async throws -> MCPCallResult {
            calls.append((name, arguments))
            return MCPCallResult(content: #"{"deleted":true}"#)
        }

        var callCount: Int { calls.count }
    }

    @Test
    func traceReconstructsParentChildTimelineAndRedactsToolPayloads() async throws {
        let secret = "sk-phase910-secret-value"
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(
                    id: "echo-1",
                    name: "echo_secret",
                    arguments: #"{"value":"sk-phase910-secret-value"}"#
                )]
            ),
            ModelResponse(
                content: "done",
                usage: AgentUsage(inputTokens: 4, outputTokens: 2, totalTokens: 6)
            )
        ])
        let tracer = InMemoryAgentTracer()
        let session = MemoryAgentSession(
            id: "trace-session",
            items: [.compaction(CompactionItem(summary: "old summary", summarizedItemCount: 8))]
        )
        let agent = AgentDefinition<Void, String>(
            id: "trace-agent",
            name: "Trace Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(EchoTool())],
            inputGuardrails: [AnyInputGuardrail(AllowInputGuardrail())],
            toolGuardrails: [AnyToolGuardrail(AllowToolGuardrail())]
        )

        let result = try await AgentRunner(provider: provider, tracer: tracer).run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: session,
            configuration: RunConfiguration(retryPolicy: .none)
        ).result.value
        let records = await tracer.records()

        #expect(result.finalOutput == "done")
        #expect(records.first?.definition.kind == .run)
        #expect(records.contains(where: { $0.definition.kind == .agent }))
        #expect(records.filter { $0.definition.kind == .model }.count == 2)
        #expect(records.contains(where: { $0.definition.kind == .tool }))
        #expect(records.contains(where: { $0.definition.kind == .guardrail }))
        #expect(records.contains(where: { $0.definition.kind == .compaction }))
        #expect(records.allSatisfy { $0.outcome != nil })

        let recordsByID = Dictionary(uniqueKeysWithValues: records.map {
            ($0.definition.spanID, $0)
        })
        for record in records where record.definition.parentSpanID != nil {
            #expect(recordsByID[record.definition.parentSpanID!] != nil)
        }
        let serialized = String(
            data: try JSONEncoder().encode(records),
            encoding: .utf8
        ) ?? ""
        #expect(!serialized.contains(secret))
        let run = try #require(records.first(where: { $0.definition.kind == .run }))
        #expect(run.outcome?.usage?.totalTokens == 6)
    }

    @Test
    func localTracePersistenceFailureDoesNotAffectRun() async throws {
        let provider = FakeProvider([ModelResponse(content: "done")])
        let tracer = LocalAgentTracer(
            persistenceURL: URL(fileURLWithPath: "/dev/null/agent-traces.json")
        )
        let agent = AgentDefinition<Void, String>(
            id: "trace-failure",
            name: "Trace Failure",
            instructions: .fixed("system")
        )
        let result = try await AgentRunner(provider: provider, tracer: tracer).run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: MemoryAgentSession()
        ).result.value
        #expect(result.finalOutput == "done")
    }

    @Test
    func approvalRequestAndDecisionAreTracedAcrossResume() async throws {
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(
                    id: "approval-1",
                    name: "risky_trace",
                    arguments: #"{"value":"ok"}"#
                )]
            ),
            ModelResponse(content: "done")
        ])
        let tracer = InMemoryAgentTracer()
        let runner = AgentRunner(provider: provider, tracer: tracer)
        let session = MemoryAgentSession(id: "approval-trace")
        let agent = AgentDefinition<Void, String>(
            id: "approval-agent",
            name: "Approval Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(RiskyTool())]
        )
        let paused = try await runner.run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: session
        ).result.value
        let interruption = try #require(paused.interruptions.first)
        let state = try #require(paused.resumableState)
        _ = try await runner.resume(
            agent: agent,
            from: state,
            decisions: [interruption.id: .approved],
            context: (),
            session: session
        ).result.value

        let approvals = await tracer.records().filter { $0.definition.kind == .approval }
        #expect(approvals.count == 2)
        #expect(approvals.contains(where: { $0.outcome?.status == .interrupted }))
        #expect(approvals.contains(where: { record in
            record.events.contains(.approval(decision: "approved"))
        }))
        #expect(Set(approvals.map(\.definition.traceID)).count == 1)
    }

    @Test
    func agentAsToolReturnsStructuredResultAndKeepsNestedTraceParentage() async throws {
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(
                    id: "expert-call",
                    name: "ask_document_expert",
                    arguments: #"{"input":"summarize only this"}"#
                )]
            ),
            ModelResponse(content: "expert summary"),
            ModelResponse(content: "main final")
        ])
        let tracer = InMemoryAgentTracer()
        let runner = AgentRunner(provider: provider, tracer: tracer)
        let expert = AgentDefinition<Void, String>(
            id: "document-expert",
            name: "Document Expert",
            instructions: .fixed("expert system")
        )
        let expertTool = AgentAsTool.make(
            name: "ask_document_expert",
            description: "Delegate a document summary",
            agent: expert,
            runner: runner
        )
        let main = AgentDefinition<Void, String>(
            id: "main",
            name: "Main",
            instructions: .fixed("main system"),
            tools: [expertTool]
        )

        let result = try await runner.run(
            agent: main,
            input: AgentInput("delegate"),
            context: (),
            session: MemoryAgentSession()
        ).result.value
        #expect(result.finalOutput == "main final")
        let toolResult = try #require(result.history.compactMap { item -> ToolResultItem? in
            guard case .toolResult(let value) = item,
                  value.toolName == "ask_document_expert" else { return nil }
            return value
        }.first)
        let payload = try JSONDecoder().decode(
            AgentAsToolResult.self,
            from: Data(toolResult.content.utf8)
        )
        #expect(payload.agentID == "document-expert")
        #expect(payload.output == "expert summary")
        #expect(provider.requests[1].agentID == "document-expert")
        #expect(provider.requests[1].tools.isEmpty)

        let records = await tracer.records()
        let toolSpan = try #require(records.first {
            $0.definition.kind == .tool && $0.definition.name == "ask_document_expert"
        })
        let nestedRun = try #require(records.first {
            $0.definition.kind == .run
                && $0.definition.agentID == "document-expert"
        })
        #expect(nestedRun.definition.traceID == toolSpan.definition.traceID)
        #expect(nestedRun.definition.parentSpanID == toolSpan.definition.spanID)
    }

    @Test
    func handoffChangesResponsibleAgentAndPersistsAcrossFollowingTurn() async throws {
        let target = AgentDefinition<Void, String>(
            id: "project-agent",
            name: "Project Agent",
            instructions: .fixed("project-only system")
        )
        let root = AgentDefinition<Void, String>(
            id: "desktop",
            name: "Desktop",
            instructions: .fixed("desktop system"),
            handoffs: [AgentHandoff(
                target: target,
                description: "Transfer project work",
                metadata: .object(["scope": .string("project")]),
                historyFilter: { items in
                    items.filter {
                        guard case .message(let message) = $0 else { return true }
                        return message.role != .system
                    }
                }
            )]
        )
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(
                    id: "handoff-1",
                    name: "handoff_to_project_agent",
                    arguments: #"{"reason":"project mode","metadata":{"project":"p1"}}"#
                )]
            ),
            ModelResponse(content: "project answer"),
            ModelResponse(content: "project follow-up")
        ])
        let tracer = InMemoryAgentTracer()
        let runner = AgentRunner(provider: provider, tracer: tracer)
        let session = MemoryAgentSession(id: "handoff-session")

        let first = try await runner.run(
            agent: root,
            input: AgentInput("enter project"),
            context: (),
            session: session
        ).result.value
        #expect(first.finalOutput == "project answer")
        #expect(first.lastAgentID == "project-agent")
        #expect(first.history.contains(where: {
            guard case .handoff(let item) = $0 else { return false }
            return item.sourceAgentID == "desktop"
                && item.targetAgentID == "project-agent"
                && item.reason == "project mode"
        }))
        #expect(provider.requests[1].agentID == "project-agent")
        #expect(provider.requests[1].tools.isEmpty)

        let second = try await runner.run(
            agent: root,
            input: AgentInput("continue"),
            context: (),
            session: session
        ).result.value
        #expect(second.finalOutput == "project follow-up")
        #expect(second.lastAgentID == "project-agent")
        #expect(provider.requests[2].agentID == "project-agent")

        let records = await tracer.records()
        #expect(records.contains(where: { $0.definition.kind == .handoff }))
        #expect(records.filter { $0.definition.kind == .agent }.contains(where: {
            $0.definition.agentID == "project-agent"
        }))
    }

    @Test
    func mcpToolsApplyFilterApprovalAndUnifiedGuardrails() async throws {
        let descriptor = MCPToolDescriptor(
            name: "delete_file",
            description: "Delete a file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string")])
                ]),
                "required": .array([.string("path")]),
                "additionalProperties": .bool(false)
            ]),
            isReadOnly: false,
            isIdempotent: false,
            hasExternalSideEffects: true
        )
        let hidden = MCPToolDescriptor(
            name: "hidden",
            description: "Hidden",
            inputSchema: .object(["type": .string("object")])
        )
        let client = FakeMCPClient(descriptors: [descriptor, hidden])
        let server = MCPServerConfiguration(
            id: "private-files",
            label: "Private Files",
            endpoint: URL(string: "https://mcp.internal.example/tools")!,
            networkBoundary: .privateNetwork
        )
        let mcp = MCPToolProvider<Void>(
            server: server,
            client: client,
            approvalPolicy: .mutations,
            filter: MCPToolFilter(allowedNames: ["delete_file"])
        )
        let tools = try await mcp.tools()
        let tool = try #require(tools.first)
        #expect(tools.count == 1)
        #expect(tool.definition.name == "mcp_private_files_delete_file")

        let call = ToolCallItem(
            id: "mcp-1",
            name: tool.definition.name,
            arguments: #"{"path":"/safe/file"}"#
        )
        let provider = FakeProvider([
            ModelResponse(content: "", toolCalls: [call]),
            ModelResponse(content: "done")
        ])
        let runner = AgentRunner(provider: provider, tracer: InMemoryAgentTracer())
        let session = MemoryAgentSession(id: "mcp-approval")
        let agent = AgentDefinition<Void, String>(
            id: "mcp-agent",
            name: "MCP Agent",
            instructions: .fixed("system"),
            tools: tools
        )
        let paused = try await runner.run(
            agent: agent,
            input: AgentInput("delete"),
            context: (),
            session: session
        ).result.value
        #expect(paused.interruptions.count == 1)
        #expect(await client.callCount == 0)
        let interruption = try #require(paused.interruptions.first)
        let state = try #require(paused.resumableState)
        let completed = try await runner.resume(
            agent: agent,
            from: state,
            decisions: [interruption.id: .approved],
            context: (),
            session: session
        ).result.value
        #expect(completed.finalOutput == "done")
        #expect(await client.callCount == 1)

        let blockedProvider = FakeProvider([ModelResponse(content: "", toolCalls: [call])])
        let blockedAgent = AgentDefinition<Void, String>(
            id: "blocked-mcp",
            name: "Blocked MCP",
            instructions: .fixed("system"),
            tools: tools,
            toolGuardrails: [AnyToolGuardrail(BlockToolGuardrail())]
        )
        do {
            _ = try await AgentRunner(provider: blockedProvider).run(
                agent: blockedAgent,
                input: AgentInput("delete"),
                context: (),
                session: MemoryAgentSession()
            ).result.value
            Issue.record("MCP Tool Guardrail 应阻止调用")
        } catch let error as AgentError {
            guard case .guardrailTriggered = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
        }
        #expect(await client.callCount == 1)
    }

    @Test
    func mcpNetworkBoundaryRejectsInsecureRemoteEndpoint() async {
        let client = FakeMCPClient(descriptors: [])
        let provider = MCPToolProvider<Void>(
            server: MCPServerConfiguration(
                id: "remote",
                label: "Remote",
                endpoint: URL(string: "http://example.com/mcp")!,
                networkBoundary: .remoteHTTPS
            ),
            client: client
        )
        do {
            _ = try await provider.tools()
            Issue.record("远程 MCP 不应允许非 HTTPS endpoint")
        } catch let error as AgentError {
            guard case .invalidConfiguration = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }
}
