import Foundation
import Testing
@testable import 看板娘

struct AgentCoreTests {
    private final class FakeProvider: AgentModelProvider, @unchecked Sendable {
        let id = "fake"
        let capabilities = ModelCapabilities.chatCompletions
        private let lock = NSLock()
        private var responses: [ModelResponse]
        private(set) var requests: [ModelRequest] = []

        init(_ responses: [ModelResponse]) {
            self.responses = responses
        }

        func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
            lock.lock()
            requests.append(request)
            let response = responses.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                if !response.content.isEmpty {
                    continuation.yield(.textDelta(response.content))
                }
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }
    }

    private struct EchoArguments: Codable, Sendable {
        let value: String
    }

    private struct EchoOutput: Codable, Sendable {
        let value: String
    }

    private struct EchoTool: AgentTool {
        typealias Context = String
        typealias Arguments = EchoArguments
        typealias Output = EchoOutput

        static let definition = ToolDefinition(
            name: "echo",
            description: "echo",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")])
                ])
            ])
        )

        func invoke(context: ToolContext<String>, arguments: EchoArguments) async throws -> EchoOutput {
            EchoOutput(value: "\(context.context):\(arguments.value)")
        }
    }

    private struct RiskyEchoTool: AgentTool {
        typealias Context = String
        typealias Arguments = EchoArguments
        typealias Output = EchoOutput

        static let definition = ToolDefinition(name: "risky_echo", description: "risky echo")
        static let behavior = ToolBehavior.mutating

        func invoke(context: ToolContext<String>, arguments: EchoArguments) async throws -> EchoOutput {
            EchoOutput(value: arguments.value)
        }
    }

    @Test
    func runnerReturnsStructuredResultAndStableEvents() async throws {
        let provider = FakeProvider([
            ModelResponse(content: "完成", usage: AgentUsage(inputTokens: 3, outputTokens: 2, totalTokens: 5))
        ])
        let runner = AgentRunner(provider: provider)
        let session = MemoryAgentSession(id: "session-1")
        let agent = AgentDefinition<String, String>(
            id: "desktop",
            name: "Desktop Agent",
            instructions: .fixed("system")
        )

        let run = runner.run(
            agent: agent,
            input: AgentInput("请执行"),
            context: "context",
            session: session
        )
        let result = try await run.result.value
        var events: [AgentRunEvent] = []
        for try await event in run.events { events.append(event) }

        #expect(result.finalOutput == "完成")
        #expect(result.usage.totalTokens == 5)
        #expect(result.newItems.count == 3)
        #expect(events.first == .runStarted(RunSnapshot(
            runID: result.runID,
            sessionID: "session-1",
            startedAt: {
                if case .runStarted(let snapshot) = events.first { return snapshot.startedAt }
                return .distantPast
            }()
        )))
        #expect(events.last == .runCompleted)
        #expect(await session.loadItems() == result.history)
    }

    @Test
    func runnerExecutesTypedToolAndContinuesModelLoop() async throws {
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(id: "call-1", name: "echo", arguments: #"{"value":"ok"}"#)]
            ),
            ModelResponse(content: "工具已完成")
        ])
        let runner = AgentRunner(provider: provider)
        let agent = AgentDefinition<String, String>(
            id: "desktop",
            name: "Desktop Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(EchoTool())]
        )

        let result = try await runner.run(
            agent: agent,
            input: AgentInput("echo"),
            context: "ctx",
            session: MemoryAgentSession()
        ).result.value

        #expect(result.finalOutput == "工具已完成")
        #expect(result.rawResponses.count == 2)
        #expect(result.newItems.contains(where: {
            guard case .toolResult(let item) = $0 else { return false }
            return !item.isError && item.content.contains("ctx:ok")
        }))
    }

    @Test
    func runnerStopsAtConfiguredMaximumTurns() async {
        let repeated = ModelResponse(
            content: "",
            toolCalls: [ToolCallItem(id: UUID().uuidString, name: "echo", arguments: #"{"value":"ok"}"#)]
        )
        let provider = FakeProvider([repeated, repeated, repeated])
        let runner = AgentRunner(provider: provider)
        let agent = AgentDefinition<String, String>(
            id: "desktop",
            name: "Desktop Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(EchoTool())]
        )

        do {
            _ = try await runner.run(
                agent: agent,
                input: AgentInput("loop"),
                context: "ctx",
                session: MemoryAgentSession(),
                configuration: RunConfiguration(maxTurns: 2, retryPolicy: .none)
            ).result.value
            Issue.record("应该触发 maxTurnsExceeded")
        } catch let error as AgentError {
            #expect(error == .maxTurnsExceeded(limit: 2))
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }

    @Test
    func invalidRunConfigurationFailsBeforeProviderRequest() async {
        let provider = FakeProvider([ModelResponse(content: "unused")])
        let runner = AgentRunner(provider: provider)
        let agent = AgentDefinition<String, String>(
            id: "desktop",
            name: "Desktop Agent",
            instructions: .fixed("system")
        )

        do {
            _ = try await runner.run(
                agent: agent,
                input: AgentInput("test"),
                context: "ctx",
                session: MemoryAgentSession(),
                configuration: RunConfiguration(maxTurns: 0)
            ).result.value
            Issue.record("应该拒绝无效配置")
        } catch let error as AgentError {
            guard case .invalidConfiguration = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
            #expect(provider.requests.isEmpty)
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }

    @Test
    func approvalProducesSerializableResumableState() async throws {
        let provider = FakeProvider([
            ModelResponse(
                content: "",
                toolCalls: [ToolCallItem(
                    id: "risky-1",
                    name: "risky_echo",
                    arguments: #"{"value":"do it"}"#
                )]
            )
        ])
        let runner = AgentRunner(provider: provider)
        let session = MemoryAgentSession(id: "approval-session")
        let agent = AgentDefinition<String, String>(
            id: "desktop",
            name: "Desktop Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(RiskyEchoTool())]
        )

        let result = try await runner.run(
            agent: agent,
            input: AgentInput("mutate"),
            context: "ctx",
            session: session
        ).result.value

        #expect(result.finalOutput == nil)
        #expect(result.interruptions.count == 1)
        #expect(result.resumableState?.sessionID == "approval-session")
        #expect(await session.loadRunState() == result.resumableState)
        #expect(try JSONEncoder().encode(result.resumableState).isEmpty == false)
    }
}
