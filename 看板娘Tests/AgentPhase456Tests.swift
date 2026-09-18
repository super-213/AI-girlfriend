import Foundation
import Testing
@testable import 看板娘

struct AgentPhase456Tests {
    @MainActor
    private final class RuntimeClient: AgentModelClient {
        var responses: [AgentModelResponse]
        let contextWindowConfigurationIdentifier = "runtime-test"

        init(responses: [AgentModelResponse]) {
            self.responses = responses
        }

        func sendAgentStreamRequest(
            messages: [AgentMessage],
            tools: [AgentToolDefinition],
            purpose: AgentRequestPurpose,
            onReceive: @escaping @MainActor @Sendable (String) -> Void,
            onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
            onError: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            let response = responses.removeFirst()
            if !response.content.isEmpty { onReceive(response.content) }
            onComplete(response)
        }

        func cancelStreamRequest() {}
    }

    private final class FakeProvider: AgentModelProvider, @unchecked Sendable {
        let id = "phase-456-fake"
        let capabilities: ModelCapabilities
        private let lock = NSLock()
        private var responses: [ModelResponse]
        private(set) var requestCount = 0

        init(_ responses: [ModelResponse], supportsParallelTools: Bool = false) {
            self.responses = responses
            capabilities = ModelCapabilities(
                supportsTools: true,
                supportsParallelTools: supportsParallelTools,
                supportsStructuredOutput: false,
                supportsImageInput: false,
                supportsServerManagedState: false,
                supportsPromptCaching: false,
                supportsResponsesAPI: false
            )
        }

        func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
            lock.lock()
            requestCount += 1
            let response = responses.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }
    }

    private struct ValueArguments: Codable, Sendable { let value: String }
    private struct ValueOutput: Codable, Sendable { let value: String }

    private actor InvocationCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private struct ValidatedTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput

        static let definition = ToolDefinition(
            name: "validated",
            description: "validated",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")])
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false)
            ])
        )

        let counter: InvocationCounter

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            await counter.increment()
            return ValueOutput(value: arguments.value)
        }
    }

    private actor ParallelProbe {
        private var active = 0
        private(set) var maximumActive = 0

        func enter() {
            active += 1
            maximumActive = max(maximumActive, active)
        }

        func leave() { active -= 1 }
    }

    private struct SlowReadTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput

        static let definition = ToolDefinition(name: "slow_read", description: "slow read")
        static let behavior = ToolBehavior.readOnly
        let probe: ParallelProbe

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            await probe.enter()
            try await Task.sleep(for: .milliseconds(80))
            await probe.leave()
            return ValueOutput(value: arguments.value)
        }
    }

    private struct RiskyTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput

        static let definition = ToolDefinition(name: "risky", description: "risky")
        static let behavior = ToolBehavior.mutating
        let counter: InvocationCounter

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            await counter.increment()
            return ValueOutput(value: arguments.value)
        }
    }

    @MainActor
    private final class HangingLegacyTool: LegacyAgentTool {
        let definition = AgentToolDefinition(
            name: "hanging_legacy",
            description: "never completes",
            parameters: ["type": "object", "properties": [:]]
        )
        let requiresConfirmation = false

        func approvalSummary(arguments: [String: Any]) -> String { "hang" }

        func execute(
            arguments: [String: Any],
            completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
        ) {
            // Deliberately never calls back; cancellation must release the adapter.
        }
    }

    @Test
    func typedToolRejectsSchemaViolationsBeforeInvocation() async throws {
        let counter = InvocationCounter()
        let tool = AnyAgentTool(ValidatedTool(counter: counter))
        let context = ToolContext(runID: UUID(), sessionID: "s", agentID: "a", context: ())

        do {
            _ = try await tool.invoke(context: context, arguments: #"{"value":1,"extra":true}"#)
            Issue.record("参数应在调用工具前被拒绝")
        } catch let error as AgentError {
            guard case .invalidToolArguments = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
        }
        #expect(await counter.count == 0)
    }

    @Test @MainActor
    func legacyToolAdapterReturnsWhenCancelled() async {
        let tool = LegacyToolAdapter<Void>.erase(HangingLegacyTool())
        let task = Task {
            try await tool.invoke(
                context: ToolContext(
                    runID: UUID(),
                    sessionID: "cancel-legacy",
                    agentID: "agent",
                    context: ()
                ),
                arguments: "{}"
            )
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("取消后兼容工具不应继续等待 callback")
        } catch let error as AgentError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }

    @Test
    func safeReadOnlyToolsUseBoundedParallelExecution() async throws {
        let calls = (0..<4).map {
            ToolCallItem(id: "call-\($0)", name: "slow_read", arguments: #"{"value":"ok"}"#)
        }
        let provider = FakeProvider(
            [ModelResponse(content: "", toolCalls: calls), ModelResponse(content: "done")],
            supportsParallelTools: true
        )
        let probe = ParallelProbe()
        let agent = AgentDefinition<Void, String>(
            id: "parallel-agent",
            name: "Parallel Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(SlowReadTool(probe: probe))]
        )
        let result = try await AgentRunner(provider: provider).run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: MemoryAgentSession(),
            configuration: RunConfiguration(maximumConcurrentTools: 2, retryPolicy: .none)
        ).result.value

        #expect(result.finalOutput == "done")
        #expect(await probe.maximumActive == 2)
    }

    @Test
    func multipleApprovalsCanBeResolvedIncrementallyWithoutRepeatingModelTurn() async throws {
        let calls = [
            ToolCallItem(id: "risk-1", name: "risky", arguments: #"{"value":"one"}"#),
            ToolCallItem(id: "risk-2", name: "risky", arguments: #"{"value":"two"}"#)
        ]
        let provider = FakeProvider([
            ModelResponse(content: "", toolCalls: calls),
            ModelResponse(content: "done")
        ])
        let counter = InvocationCounter()
        let runner = AgentRunner(provider: provider)
        let session = MemoryAgentSession(id: "multi-approval")
        let agent = AgentDefinition<Void, String>(
            id: "approval-agent",
            name: "Approval Agent",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(RiskyTool(counter: counter))]
        )

        let first = try await runner.run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: session
        ).result.value
        #expect(first.interruptions.count == 2)
        #expect(provider.requestCount == 1)

        let firstState = try #require(first.resumableState)
        let firstApproval = try #require(first.interruptions.first)
        let partial = try await runner.resume(
            agent: agent,
            from: firstState,
            decisions: [firstApproval.id: .approved],
            context: (),
            session: session
        ).result.value
        #expect(partial.interruptions.count == 1)
        #expect(await counter.count == 0)
        #expect(provider.requestCount == 1)

        let partialState = try #require(partial.resumableState)
        let secondApproval = try #require(partial.interruptions.first)
        let completed = try await runner.resume(
            agent: agent,
            from: partialState,
            decisions: [secondApproval.id: .rejected(reason: "skip")],
            context: (),
            session: session
        ).result.value

        #expect(completed.runID == first.runID)
        #expect(completed.finalOutput == "done")
        #expect(await counter.count == 1)
        #expect(provider.requestCount == 2)
        #expect(await session.loadRunState() == nil)
    }

    @Test
    func persistentAndExpiringSessionsPreserveAndExpireStructuredState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-session-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("session.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = AgentItem.message(AgentMessageItem(role: .user, content: "hello"))
        let runID = UUID()
        let call = ToolCallItem(id: "pending", name: "risky", arguments: "{}")
        let interruption = AgentInterruption(
            runID: runID,
            toolCall: call,
            summary: "approve",
            riskLevel: .high
        )
        let state = RunState(
            runID: runID,
            currentAgentID: "desktop-companion",
            turn: 1,
            completedItems: [item, .toolCall(call)],
            pendingToolCalls: [call],
            interruptions: [interruption],
            traceID: UUID(),
            sessionID: "persisted"
        )
        let persistent = try PersistentAgentSession(fileURL: file, id: "persisted")
        try await persistent.replaceItems([item])
        try await persistent.saveRunState(state)
        let reopened = try PersistentAgentSession(fileURL: file)
        #expect(reopened.id == "persisted")
        #expect(await reopened.loadItems() == [item])
        #expect(await reopened.loadRunState() == state)

        final class Clock: @unchecked Sendable {
            let lock = NSLock()
            var value = Date(timeIntervalSince1970: 100)
            func now() -> Date { lock.withLock { value } }
            func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
        }
        let clock = Clock()
        let expiring = ExpiringAgentSession(
            id: "expiring",
            items: [item],
            timeout: 10,
            lastAccessAt: clock.now(),
            now: clock.now
        )
        clock.advance(11)
        #expect(await expiring.loadItems().isEmpty)
    }

    @Test @MainActor
    func approvalSnapshotRestoresAndResumesAfterRuntimeRecreation() async throws {
        let counter = InvocationCounter()
        let registry = AgentToolRegistry()
        registry.register(RiskyTool(counter: counter))
        let client = RuntimeClient(responses: [
            AgentModelResponse(
                content: "",
                toolCalls: [AgentToolCall(
                    id: "restart-risk",
                    name: "risky",
                    arguments: #"{"value":"once"}"#
                )]
            ),
            AgentModelResponse(content: "resumed", toolCalls: [])
        ])
        let firstRuntime = AgentRuntime(
            apiManager: client,
            registry: registry,
            systemPromptProvider: { "system" }
        )
        firstRuntime.send("run")
        while firstRuntime.sessionSnapshot.pendingRunState == nil {
            await Task.yield()
        }
        let saved = firstRuntime.sessionSnapshot

        let restoredRuntime = AgentRuntime(
            apiManager: client,
            registry: registry,
            systemPromptProvider: { "system" }
        )
        var requestedApproval = false
        restoredRuntime.onApprovalRequested = { _ in requestedApproval = true }
        restoredRuntime.restoreSession(saved)
        #expect(requestedApproval)

        restoredRuntime.approvePendingTool()
        while restoredRuntime.isRunning { await Task.yield() }

        #expect(await counter.count == 1)
        #expect(restoredRuntime.sessionSnapshot.pendingRunState == nil)
        #expect(restoredRuntime.messages.contains(where: {
            $0.role == .assistant && $0.content == "resumed"
        }))
    }

    @Test
    func sessionCoordinatorRejectsConcurrentRunsForTheSameSession() async {
        let coordinator = AgentSessionRunCoordinator()
        let first = UUID()
        let second = UUID()
        #expect(await coordinator.acquire(sessionID: "shared", runID: first))
        #expect(await coordinator.acquire(sessionID: "shared", runID: second) == false)
        await coordinator.release(sessionID: "shared", runID: first)
        #expect(await coordinator.acquire(sessionID: "shared", runID: second))
        await coordinator.release(sessionID: "shared", runID: second)
    }

    @Test @MainActor
    func incompatiblePersistedRunStateFailsClosed() {
        let runID = UUID()
        let call = ToolCallItem(id: "unsafe", name: "risky", arguments: "{}")
        let state = RunState(
            schemaVersion: RunState.currentSchemaVersion - 1,
            runID: runID,
            currentAgentID: "desktop-companion",
            turn: 1,
            completedItems: [],
            pendingToolCalls: [call],
            interruptions: [AgentInterruption(
                runID: runID,
                toolCall: call,
                summary: "unsafe",
                riskLevel: .high
            )],
            traceID: UUID(),
            sessionID: "incompatible"
        )
        let snapshot = AgentSessionSnapshot(
            sessionID: "incompatible",
            pendingRunState: state
        )
        let runtime = AgentRuntime(
            apiManager: RuntimeClient(responses: []),
            registry: AgentToolRegistry(),
            systemPromptProvider: { "system" }
        )
        var receivedError: AgentError?
        runtime.onError = { receivedError = $0 as? AgentError }

        runtime.restoreSession(snapshot)

        #expect(receivedError == .approvalStateInvalid)
        #expect(runtime.isRunning == false)
    }

    @Test
    func legacyConversationDecodingMigratesToSessionSnapshot() throws {
        let conversation = DialogConversation(agentHistory: [.user("legacy")])
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(conversation)) as? [String: Any]
        )
        object.removeValue(forKey: "agentSession")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(DialogConversation.self, from: legacyData)

        #expect(migrated.agentSession.sessionID == migrated.id.uuidString)
        #expect(migrated.agentSession.legacyMessages == [.user("legacy")])
    }
}
