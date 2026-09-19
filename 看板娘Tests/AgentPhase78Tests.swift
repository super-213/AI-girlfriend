import Foundation
import Testing
@testable import 看板娘

struct AgentPhase78Tests {
    private final class RecordingTransport: AgentHTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private let lines: [String]
        private var recordedRequests: [URLRequest] = []

        init(lines: [String]) {
            self.lines = lines
        }

        func streamLines(
            request: URLRequest,
            runID: UUID
        ) -> AsyncThrowingStream<String, Error> {
            lock.withLock { recordedRequests.append(request) }
            let lines = lines
            return AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }

        func cancel(runID: UUID) async {}

        func lastRequest() -> URLRequest? {
            lock.withLock { recordedRequests.last }
        }
    }

    private final class FakeProvider: AgentModelProvider, @unchecked Sendable {
        let id = "phase-78-fake"
        let capabilities: ModelCapabilities
        private let lock = NSLock()
        private var responses: [ModelResponse]
        private var recordedRequests: [ModelRequest] = []

        init(
            _ responses: [ModelResponse],
            capabilities: ModelCapabilities = ModelCapabilities(
                supportsTools: true,
                supportsParallelTools: true,
                supportsStructuredOutput: true,
                supportsImageInput: true,
                supportsServerManagedState: false,
                supportsPromptCaching: false,
                supportsResponsesAPI: false
            )
        ) {
            self.responses = responses
            self.capabilities = capabilities
        }

        func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
            let response = lock.withLock {
                recordedRequests.append(request)
                return responses.removeFirst()
            }
            return AsyncThrowingStream { continuation in
                if !response.content.isEmpty { continuation.yield(.textDelta(response.content)) }
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }

        var requestCount: Int { lock.withLock { recordedRequests.count } }
        var lastRequest: ModelRequest? { lock.withLock { recordedRequests.last } }
    }

    private final class ChunkedProvider: AgentModelProvider, @unchecked Sendable {
        let id = "phase-78-chunked"
        let capabilities = ModelCapabilities(
            supportsTools: true,
            supportsParallelTools: true,
            supportsStructuredOutput: true,
            supportsImageInput: true,
            supportsServerManagedState: false,
            supportsPromptCaching: false,
            supportsResponsesAPI: false
        )
        private let chunks: [String]
        private let response: ModelResponse

        init(chunks: [String]) {
            self.chunks = chunks
            response = ModelResponse(content: chunks.joined())
        }

        func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
            let chunks = chunks
            let response = response
            return AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(.textDelta(chunk)) }
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }
    }

    private struct ValueArguments: Codable, Sendable { let value: String }
    private struct ValueOutput: Codable, Sendable { let value: String }
    private struct StructuredOutput: Codable, Equatable, Sendable { let answer: String }

    private actor InvocationCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private struct ReadTool: AgentTool {
        typealias Context = Void
        typealias Arguments = ValueArguments
        typealias Output = ValueOutput

        static let definition = ToolDefinition(
            name: "read_value",
            description: "Read a value",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")])
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false)
            ])
        )
        static let behavior = ToolBehavior.readOnly
        let counter: InvocationCounter

        func invoke(context: ToolContext<Void>, arguments: ValueArguments) async throws -> ValueOutput {
            await counter.increment()
            return ValueOutput(value: arguments.value)
        }
    }

    private struct BlockingInputGuardrail: InputGuardrail {
        let name = "blocking_input"
        func evaluate(
            context: AgentGuardrailContext<Void>,
            input: AgentInput
        ) async throws -> GuardrailResult {
            GuardrailResult(action: .stop, message: "input blocked")
        }
    }

    private struct FailingInputGuardrail: InputGuardrail {
        let name = "failing_input"
        struct Failure: Error {}
        func evaluate(
            context: AgentGuardrailContext<Void>,
            input: AgentInput
        ) async throws -> GuardrailResult {
            throw Failure()
        }
    }

    private struct AllowingInputGuardrail: InputGuardrail {
        let name = "allowing_input"
        func evaluate(
            context: AgentGuardrailContext<Void>,
            input: AgentInput
        ) async throws -> GuardrailResult { .allowed }
    }

    private struct BlockingOutputGuardrail: OutputGuardrail {
        let name = "blocking_output"
        func evaluate(
            context: AgentGuardrailContext<Void>,
            output: String
        ) async throws -> GuardrailResult {
            GuardrailResult(action: .stop, message: "output blocked")
        }
    }

    private struct ApprovalToolGuardrail: ToolGuardrail {
        let name = "approval_tool"
        func evaluateInput(
            context: AgentGuardrailContext<Void>,
            call: ToolCallItem,
            tool: ToolDefinition
        ) async throws -> GuardrailResult {
            GuardrailResult(action: .requireApproval, message: "approve guarded tool")
        }
    }

    private struct BlockingToolOutputGuardrail: ToolGuardrail {
        let name = "blocking_tool_output"
        func evaluateInput(
            context: AgentGuardrailContext<Void>,
            call: ToolCallItem,
            tool: ToolDefinition
        ) async throws -> GuardrailResult { .allowed }

        func evaluateOutput(
            context: AgentGuardrailContext<Void>,
            call: ToolCallItem,
            result: ToolResultItem
        ) async throws -> GuardrailResult {
            GuardrailResult(action: .stop, message: "tool output blocked")
        }
    }

    private static let schema = AgentOutputSchema(
        name: "answer",
        description: "A structured answer",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "answer": .object(["type": .string("string")])
            ]),
            "required": .array([.string("answer")]),
            "additionalProperties": .bool(false)
        ])
    )

    private static func modelRequest(outputSchema: AgentOutputSchema? = schema) -> ModelRequest {
        ModelRequest(
            runID: UUID(),
            agentID: "contract-agent",
            model: AgentModelConfiguration(providerID: "provider", modelID: "contract-model"),
            items: [
                .message(AgentMessageItem(role: .system, content: "system instructions")),
                .message(AgentMessageItem(role: .user, content: "hello")),
                .toolCall(ToolCallItem(id: "previous-call", name: "lookup", arguments: "{}")),
                .toolResult(ToolResultItem(
                    toolCallID: "previous-call",
                    toolName: "lookup",
                    content: "previous result",
                    isError: false
                ))
            ],
            tools: [ToolDefinition(
                name: "lookup",
                description: "Lookup",
                parameters: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false)
                ])
            )],
            outputSchema: outputSchema
        )
    }

    private static func collect(
        _ provider: any AgentModelProvider,
        request: ModelRequest
    ) async throws -> [ModelStreamEvent] {
        var events: [ModelStreamEvent] = []
        for try await event in provider.streamResponse(request: request) { events.append(event) }
        return events
    }

    private static func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try #require(request?.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func openAIResponsesProviderSerializesResponsesSemanticsAndParsesStream() async throws {
        let transport = RecordingTransport(lines: [
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"hel"}"#,
            "event: response.completed",
            #"data: {"type":"response.completed","response":{"id":"resp-1","output":[{"type":"message","content":[{"type":"output_text","text":"hello"}]},{"type":"function_call","call_id":"call-1","name":"lookup","arguments":"{\"q\":\"x\"}"}],"usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}"#
        ])
        let provider = OpenAIResponsesProvider(
            configuration: AgentProviderConfiguration(
                id: "openai",
                endpoint: URL(string: "https://api.openai.com/v1/responses")!,
                model: "fallback",
                apiKey: "secret"
            ),
            transport: transport
        )

        let events = try await Self.collect(provider, request: Self.modelRequest())
        let payload = try Self.body(transport.lastRequest())
        #expect(transport.lastRequest()?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(payload["model"] as? String == "contract-model")
        #expect(payload["parallel_tool_calls"] as? Bool == true)
        #expect(payload["instructions"] as? String == "system instructions")
        #expect((payload["input"] as? [[String: Any]])?.contains(where: {
            $0["type"] as? String == "function_call_output"
        }) == true)
        #expect(((payload["text"] as? [String: Any])?["format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect(events.first == .textDelta("hel"))
        guard case .completed(let response) = events.last else {
            Issue.record("Responses Provider 应返回 completed")
            return
        }
        #expect(response.id == "resp-1")
        #expect(response.content == "hello")
        #expect(response.toolCalls == [ToolCallItem(id: "call-1", name: "lookup", arguments: #"{"q":"x"}"#)])
        #expect(response.usage?.totalTokens == 10)
    }

    @Test
    func openAICompatibleProviderSerializesChatAndReassemblesFragmentedToolCall() async throws {
        let transport = RecordingTransport(lines: [
            #"data: {"id":"chat-1","choices":[{"delta":{"content":"ok"}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-","function":{"name":"look","arguments":"{\"q\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"1","function":{"name":"up","arguments":"\"x\"}"}}]}}]}"#,
            #"data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}"#,
            "data: [DONE]"
        ])
        let provider = OpenAICompatibleChatProvider(
            configuration: AgentProviderConfiguration(
                id: "compatible",
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "fallback",
                apiKey: "key"
            ),
            transport: transport
        )

        let events = try await Self.collect(provider, request: Self.modelRequest())
        let payload = try Self.body(transport.lastRequest())
        #expect(payload["messages"] as? [[String: Any]] != nil)
        #expect(payload["tools"] as? [[String: Any]] != nil)
        #expect((payload["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect(((payload["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])?["name"] as? String == "answer")
        guard case .completed(let response) = events.last else {
            Issue.record("Compatible Provider 应返回 completed")
            return
        }
        #expect(response.content == "ok")
        #expect(response.toolCalls == [ToolCallItem(id: "call-1", name: "lookup", arguments: #"{"q":"x"}"#)])
        #expect(response.usage?.totalTokens == 6)
    }

    @Test
    func zhipuProviderUsesItsOwnRequestPolicyAndParsesChatStream() async throws {
        let transport = RecordingTransport(lines: [
            #"data: {"id":"zhipu-1","choices":[{"delta":{"content":"你好"}}]}"#,
            "data: [DONE]"
        ])
        let provider = ZhipuChatProvider(
            configuration: AgentProviderConfiguration(
                id: "zhipu",
                endpoint: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
                model: "glm-test",
                apiKey: "zhipu-key"
            ),
            transport: transport
        )

        let events = try await Self.collect(provider, request: Self.modelRequest(outputSchema: nil))
        let payload = try Self.body(transport.lastRequest())
        #expect(payload["temperature"] as? Double == 0.7)
        #expect(payload["stream_options"] == nil)
        #expect(provider.capabilities.supportsStructuredOutput == false)
        guard case .completed(let response) = events.last else {
            Issue.record("智谱 Provider 应返回 completed")
            return
        }
        #expect(response.id == "zhipu-1")
        #expect(response.content == "你好")
    }

    @Test
    func ollamaProviderSerializesLocalChatAndParsesToolAndUsage() async throws {
        let transport = RecordingTransport(lines: [
            #"{"message":{"content":"local","tool_calls":[{"id":"ollama-1","function":{"name":"lookup","arguments":{"q":"x"}}}]},"done":false}"#,
            #"{"message":{"content":""},"done":true,"prompt_eval_count":5,"eval_count":2}"#
        ])
        let provider = OllamaChatProvider(
            configuration: AgentProviderConfiguration(
                id: "ollama",
                endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
                model: "local-model",
                apiKey: "must-not-be-sent"
            ),
            transport: transport
        )

        let events = try await Self.collect(provider, request: Self.modelRequest())
        let payload = try Self.body(transport.lastRequest())
        #expect(transport.lastRequest()?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(payload["format"] as? [String: Any] != nil)
        #expect(payload["tools"] as? [[String: Any]] != nil)
        guard case .completed(let response) = events.last else {
            Issue.record("Ollama Provider 应返回 completed")
            return
        }
        #expect(response.content == "local")
        #expect(response.toolCalls.first?.id == "ollama-1")
        #expect(response.toolCalls.first?.arguments == #"{"q":"x"}"#)
        #expect(response.usage == AgentUsage(inputTokens: 5, outputTokens: 2, totalTokens: 7))
    }

    @Test
    func providerStreamInterruptionsAndWireErrorsRemainExplicit() async {
        let interrupted = OpenAIResponsesProvider(
            configuration: AgentProviderConfiguration(
                id: "openai",
                endpoint: URL(string: "https://api.openai.com/v1/responses")!,
                model: "model"
            ),
            transport: RecordingTransport(lines: [
                #"data: {"type":"response.output_text.delta","delta":"partial"}"#
            ])
        )
        do {
            _ = try await Self.collect(interrupted, request: Self.modelRequest())
            Issue.record("流中断不应伪装成完整响应")
        } catch let error as ModelProviderError {
            guard case .invalidResponse = error else {
                Issue.record("流中断错误类型不正确：\(error)")
                return
            }
        } catch {
            Issue.record("流中断错误类型不正确：\(error)")
        }

        let failed = OllamaChatProvider(
            configuration: AgentProviderConfiguration(
                id: "ollama",
                endpoint: URL(string: "http://127.0.0.1:11434/api/chat")!,
                model: "model"
            ),
            transport: RecordingTransport(lines: [#"{"error":"model unavailable"}"#])
        )
        do {
            _ = try await Self.collect(failed, request: Self.modelRequest())
            Issue.record("Provider 错误不应被吞掉")
        } catch let error as ModelProviderError {
            #expect(error == .transport("model unavailable"))
        } catch {
            Issue.record("Provider 错误类型不正确：\(error)")
        }
    }

    @Test
    func inputGuardrailStopsBeforeProviderAndFailuresFailClosed() async {
        for guardrail in [
            AnyInputGuardrail(BlockingInputGuardrail()),
            AnyInputGuardrail(FailingInputGuardrail())
        ] {
            let provider = FakeProvider([ModelResponse(content: "unused")])
            let agent = AgentDefinition<Void, String>(
                id: "guarded",
                name: "Guarded",
                instructions: .fixed("system"),
                inputGuardrails: [guardrail]
            )
            let run = AgentRunner(provider: provider).run(
                agent: agent,
                input: AgentInput("run"),
                context: (),
                session: MemoryAgentSession()
            )
            do {
                _ = try await run.result.value
                Issue.record("Input Guardrail 应阻止运行")
            } catch let error as AgentError {
                guard case .guardrailTriggered(let result) = error else {
                    Issue.record("错误类型不正确：\(error)")
                    continue
                }
                #expect(result.action == .stop)
                #expect(result.stage == .input)
            } catch {
                Issue.record("错误类型不正确：\(error)")
            }
            #expect(provider.requestCount == 0)
            var tracedResult: GuardrailResult?
            do {
                for try await event in run.events {
                    if case .guardrailEvaluated(let result) = event { tracedResult = result }
                }
            } catch {
                // The event stream intentionally terminates with the same guardrail error.
            }
            #expect(tracedResult?.guardrailName == guardrail.name)
            #expect(tracedResult?.action == .stop)
        }
    }

    @Test
    func allowedGuardrailResultsAreReturnedAndRecordedInHistory() async throws {
        let provider = FakeProvider([ModelResponse(content: "done")])
        let agent = AgentDefinition<Void, String>(
            id: "guarded",
            name: "Guarded",
            instructions: .fixed("system"),
            inputGuardrails: [AnyInputGuardrail(AllowingInputGuardrail())]
        )
        let result = try await AgentRunner(provider: provider).run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: MemoryAgentSession()
        ).result.value

        #expect(result.guardrailResults.count == 1)
        #expect(result.guardrailResults.first?.guardrailName == "allowing_input")
        #expect(result.guardrailResults.first?.stage == .input)
        #expect(result.history.contains(where: {
            guard case .guardrail(let item) = $0 else { return false }
            return item.result.guardrailName == "allowing_input"
        }))
    }

    @Test
    func toolGuardrailPausesForApprovalAndResumesSameRun() async throws {
        let call = ToolCallItem(id: "guarded-call", name: "read_value", arguments: #"{"value":"ok"}"#)
        let provider = FakeProvider([
            ModelResponse(content: "", toolCalls: [call]),
            ModelResponse(content: "done")
        ])
        let counter = InvocationCounter()
        let agent = AgentDefinition<Void, String>(
            id: "guarded-tool",
            name: "Guarded Tool",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(ReadTool(counter: counter))],
            toolGuardrails: [AnyToolGuardrail(ApprovalToolGuardrail())]
        )
        let session = MemoryAgentSession(id: "guarded-approval")
        let runner = AgentRunner(provider: provider)

        let paused = try await runner.run(
            agent: agent,
            input: AgentInput("run"),
            context: (),
            session: session
        ).result.value
        let interruption = try #require(paused.interruptions.first)
        let state = try #require(paused.resumableState)
        #expect(interruption.summary == "approve guarded tool")
        #expect(paused.guardrailResults.contains(where: {
            $0.action == .requireApproval && $0.toolCallID == call.id
        }))
        #expect(await counter.value == 0)

        let completed = try await runner.resume(
            agent: agent,
            from: state,
            decisions: [interruption.id: .approved],
            context: (),
            session: session
        ).result.value
        #expect(completed.runID == paused.runID)
        #expect(completed.finalOutput == "done")
        #expect(await counter.value == 1)
    }

    @Test
    func toolOutputAndFinalOutputGuardrailsStopBeforeUnsafeDataReturns() async {
        let counter = InvocationCounter()
        let toolProvider = FakeProvider([ModelResponse(
            content: "",
            toolCalls: [ToolCallItem(
                id: "tool-output-call",
                name: "read_value",
                arguments: #"{"value":"sensitive"}"#
            )]
        )])
        let toolAgent = AgentDefinition<Void, String>(
            id: "tool-output",
            name: "Tool Output",
            instructions: .fixed("system"),
            tools: [AnyAgentTool(ReadTool(counter: counter))],
            toolGuardrails: [AnyToolGuardrail(BlockingToolOutputGuardrail())]
        )
        await expectGuardrailFailure(
            AgentRunner(provider: toolProvider).run(
                agent: toolAgent,
                input: AgentInput("run"),
                context: (),
                session: MemoryAgentSession()
            ),
            stage: .toolOutput
        )

        let outputProvider = FakeProvider([ModelResponse(content: "unsafe")])
        let outputAgent = AgentDefinition<Void, String>(
            id: "output",
            name: "Output",
            instructions: .fixed("system"),
            outputGuardrails: [AnyOutputGuardrail(BlockingOutputGuardrail())]
        )
        let outputRun = AgentRunner(provider: outputProvider).run(
            agent: outputAgent,
            input: AgentInput("run"),
            context: (),
            session: MemoryAgentSession()
        )
        await expectGuardrailFailure(outputRun, stage: .output)
        var leakedUnsafeDelta = false
        do {
            for try await event in outputRun.events {
                if case .textDelta(let delta) = event, delta == "unsafe" {
                    leakedUnsafeDelta = true
                }
            }
        } catch {
            // The event stream terminates with the same guardrail failure.
        }
        #expect(!leakedUnsafeDelta)
    }

    @Test
    func streamingOutputGuardrailPreservesSafeIncrementalText() async throws {
        let chunks = [
            String(repeating: "A", count: 40),
            String(repeating: "B", count: 40),
            String(repeating: "C", count: 40)
        ]
        let provider = ChunkedProvider(chunks: chunks)
        let agent = AgentDefinition<AppAgentContext, String>(
            id: "streaming-output",
            name: "Streaming Output",
            instructions: .fixed("system"),
            outputGuardrails: [AnyOutputGuardrail(streaming: AppAgentOutputGuardrail())]
        )
        let run = AgentRunner(provider: provider).run(
            agent: agent,
            input: AgentInput("run"),
            context: AppAgentContext(conversationID: UUID()),
            session: MemoryAgentSession(),
            configuration: RunConfiguration(retryPolicy: .none)
        )

        var deltas: [String] = []
        for try await event in run.events {
            if case .textDelta(let delta) = event { deltas.append(delta) }
        }
        let result = try await run.result.value

        #expect(result.finalOutput == chunks.joined())
        #expect(deltas.joined() == chunks.joined())
        #expect(deltas.count > 1)
        #expect(deltas.first != chunks.joined())
    }

    @Test
    func streamingOutputGuardrailBlocksCredentialSplitAcrossChunks() async {
        let safePrefix = String(repeating: "safe ", count: 20)
        let provider = ChunkedProvider(chunks: [safePrefix + "sk-", "12345678"])
        let agent = AgentDefinition<AppAgentContext, String>(
            id: "streaming-sensitive-output",
            name: "Streaming Sensitive Output",
            instructions: .fixed("system"),
            outputGuardrails: [AnyOutputGuardrail(streaming: AppAgentOutputGuardrail())]
        )
        let run = AgentRunner(provider: provider).run(
            agent: agent,
            input: AgentInput("run"),
            context: AppAgentContext(conversationID: UUID()),
            session: MemoryAgentSession(),
            configuration: RunConfiguration(retryPolicy: .none)
        )

        var visibleText = ""
        do {
            for try await event in run.events {
                if case .textDelta(let delta) = event { visibleText += delta }
            }
        } catch {
            // The event stream terminates with the same guardrail failure as the result.
        }
        do {
            _ = try await run.result.value
            Issue.record("增量输出 Guardrail 应阻止跨分片凭据")
        } catch let error as AgentError {
            guard case .guardrailTriggered(let result) = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
            #expect(result.stage == .output)
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }

        #expect(!visibleText.contains("sk-"))
        #expect(!visibleText.contains("12345678"))
    }

    @Test
    func structuredOutputDecodesAndInvalidJSONNeverReachesBusinessOutput() async throws {
        let validProvider = FakeProvider([ModelResponse(content: #"{"answer":"ok"}"#)])
        let validAgent = AgentDefinition<Void, StructuredOutput>(
            id: "structured",
            name: "Structured",
            instructions: .fixed("system"),
            outputSchema: Self.schema,
            outputDecoder: .json
        )
        let validResult = try await AgentRunner(provider: validProvider).run(
            agent: validAgent,
            input: AgentInput("run"),
            context: (),
            session: MemoryAgentSession()
        ).result.value
        #expect(validResult.finalOutput == StructuredOutput(answer: "ok"))
        #expect(validProvider.lastRequest?.outputSchema == Self.schema)

        let invalidProvider = FakeProvider([ModelResponse(content: #"{"wrong":true}"#)])
        do {
            _ = try await AgentRunner(provider: invalidProvider).run(
                agent: validAgent,
                input: AgentInput("run"),
                context: (),
                session: MemoryAgentSession()
            ).result.value
            Issue.record("无效结构化输出不应返回业务层")
        } catch let error as AgentError {
            guard case .outputValidationFailed = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
        }
    }

    @Test
    func unsupportedStructuredOutputFailsBeforeProviderRequest() async {
        let capabilities = ModelCapabilities(
            supportsTools: true,
            supportsParallelTools: false,
            supportsStructuredOutput: false,
            supportsImageInput: false,
            supportsServerManagedState: false,
            supportsPromptCaching: false,
            supportsResponsesAPI: false
        )
        let provider = FakeProvider([ModelResponse(content: "unused")], capabilities: capabilities)
        let agent = AgentDefinition<Void, StructuredOutput>(
            id: "unsupported",
            name: "Unsupported",
            instructions: .fixed("system"),
            outputSchema: Self.schema,
            outputDecoder: .json
        )
        do {
            _ = try await AgentRunner(provider: provider).run(
                agent: agent,
                input: AgentInput("run"),
                context: (),
                session: MemoryAgentSession()
            ).result.value
            Issue.record("应在请求前拒绝不支持的结构化输出")
        } catch let error as AgentError {
            guard case .modelRequestFailed(.unsupportedCapability) = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
        #expect(provider.requestCount == 0)
    }

    private func expectGuardrailFailure(
        _ run: AgentRun<String>,
        stage: GuardrailStage
    ) async {
        do {
            _ = try await run.result.value
            Issue.record("Guardrail 应阻止运行")
        } catch let error as AgentError {
            guard case .guardrailTriggered(let result) = error else {
                Issue.record("错误类型不正确：\(error)")
                return
            }
            #expect(result.action == .stop)
            #expect(result.stage == stage)
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }
}
