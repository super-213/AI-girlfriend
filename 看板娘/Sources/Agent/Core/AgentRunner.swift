import Foundation

struct AgentInput: Sendable, Equatable {
    let text: String
    let imagePaths: [String]

    init(_ text: String, imagePaths: [String] = []) {
        self.text = text
        self.imagePaths = imagePaths
    }
}

protocol AgentRunning: Sendable {
    func run<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration
    ) -> AgentRun<Output>
}

final class AgentRunner: AgentRunning, Sendable {
    private let provider: any AgentModelProvider

    init(provider: any AgentModelProvider) {
        self.provider = provider
    }

    func run<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration = RunConfiguration()
    ) -> AgentRun<Output> {
        let runID = UUID()
        let stream = AsyncThrowingStream<AgentRunEvent, Error>.makeStream()
        let task = Task<RunResult<Output>, Error> {
            do {
                let result = try await self.execute(
                    runID: runID,
                    agent: agent,
                    input: input,
                    context: context,
                    session: session,
                    configuration: configuration,
                    events: stream.continuation
                )
                stream.continuation.finish()
                return result
            } catch {
                let normalized = Self.normalize(error)
                stream.continuation.yield(.runFailed(normalized))
                stream.continuation.finish(throwing: normalized)
                await self.provider.cancel(runID: runID)
                throw normalized
            }
        }
        stream.continuation.onTermination = { @Sendable termination in
            if case .cancelled = termination { task.cancel() }
        }
        return AgentRun(events: stream.stream, result: task)
    }

    private func execute<Context: Sendable, Output: Sendable>(
        runID: UUID,
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> RunResult<Output> {
        try configuration.validate()
        try Task.checkCancellation()
        guard agent.tools.isEmpty || provider.capabilities.supportsTools else {
            throw AgentError.modelRequestFailed(.unsupportedCapability("当前 Provider 不支持工具调用"))
        }
        let trimmedInput = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw AgentError.invalidConfiguration("输入不能为空")
        }

        let traceID = UUID()
        let startedAt = Date()
        let originalItems: [AgentItem]
        do {
            originalItems = try await session.loadItems()
        } catch {
            throw AgentError.sessionFailure(error.localizedDescription)
        }

        var allItems = originalItems
        var newItems: [AgentItem] = []
        let instructions = try await agent.instructions.resolve(using: context)
        if !allItems.contains(where: {
            if case .message(let message) = $0 { return message.role == .system }
            return false
        }) {
            newItems.append(.message(AgentMessageItem(role: .system, content: instructions)))
        }
        newItems.append(.message(AgentMessageItem(
            role: .user,
            content: trimmedInput,
            imagePaths: input.imagePaths
        )))
        allItems.append(contentsOf: newItems)

        events.yield(.runStarted(RunSnapshot(
            runID: runID,
            sessionID: session.id,
            startedAt: startedAt
        )))
        events.yield(.agentStarted(AgentSnapshot(id: agent.id, name: agent.name)))

        var rawResponses: [ModelResponse] = []
        var usage = AgentUsage.zero

        for turn in 1...configuration.maxTurns {
            try Task.checkCancellation()
            events.yield(.modelStarted(ModelRequestSnapshot(
                turn: turn,
                providerID: agent.model.providerID,
                modelID: agent.model.modelID
            )))

            let request = ModelRequest(
                runID: runID,
                agentID: agent.id,
                model: agent.model,
                items: allItems,
                tools: agent.tools.map(\.definition)
            )
            let response = try await requestModel(
                request,
                turn: turn,
                configuration: configuration,
                events: events
            )
            rawResponses.append(response)
            usage.add(response.usage)
            events.yield(.modelCompleted(ModelResponseSnapshot(turn: turn, response: response)))
            if response.usage != nil { events.yield(.usageUpdated(usage)) }

            let assistant = AgentItem.message(AgentMessageItem(
                role: .assistant,
                content: response.content.isEmpty ? nil : response.content
            ))
            allItems.append(assistant)
            newItems.append(assistant)
            for call in response.toolCalls {
                allItems.append(.toolCall(call))
                newItems.append(.toolCall(call))
            }

            if response.toolCalls.isEmpty {
                let output: Output
                do {
                    output = try agent.outputDecoder.decode(response.content)
                } catch let error as AgentError {
                    throw error
                } catch {
                    throw AgentError.outputValidationFailed(error.localizedDescription)
                }
                do {
                    try await session.replaceItems(allItems)
                    try await session.saveRunState(nil)
                } catch {
                    throw AgentError.sessionFailure(error.localizedDescription)
                }
                events.yield(.runCompleted)
                return RunResult(
                    runID: runID,
                    finalOutput: output,
                    history: allItems,
                    newItems: newItems,
                    lastAgentID: agent.id,
                    usage: usage,
                    rawResponses: rawResponses,
                    guardrailResults: [],
                    interruptions: [],
                    resumableState: nil
                )
            }

            for call in response.toolCalls {
                guard let tool = agent.tools.first(where: { $0.definition.name == call.name }) else {
                    let result = ToolResultItem(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: AgentError.toolUnavailable(call.name).localizedDescription,
                        isError: true
                    )
                    allItems.append(.toolResult(result))
                    newItems.append(.toolResult(result))
                    events.yield(.toolCallCompleted(result))
                    continue
                }

                if tool.behavior.requiresApproval {
                    let interruption = AgentInterruption(
                        runID: runID,
                        toolCall: call,
                        summary: "执行工具 \(call.name)",
                        riskLevel: tool.behavior.riskLevel
                    )
                    let state = RunState(
                        runID: runID,
                        currentAgentID: agent.id,
                        turn: turn,
                        completedItems: allItems,
                        pendingToolCalls: response.toolCalls,
                        interruptions: [interruption],
                        providerContinuationID: response.id,
                        traceID: traceID,
                        sessionID: session.id
                    )
                    do {
                        try await session.replaceItems(allItems)
                        try await session.saveRunState(state)
                    } catch {
                        throw AgentError.sessionFailure(error.localizedDescription)
                    }
                    events.yield(.approvalRequired(interruption))
                    return RunResult(
                        runID: runID,
                        finalOutput: nil,
                        history: allItems,
                        newItems: newItems,
                        lastAgentID: agent.id,
                        usage: usage,
                        rawResponses: rawResponses,
                        guardrailResults: [],
                        interruptions: [interruption],
                        resumableState: state
                    )
                }

                events.yield(.toolCallStarted(call))
                let toolContext = ToolContext(
                    runID: runID,
                    sessionID: session.id,
                    agentID: agent.id,
                    context: context
                )
                let timeout = tool.behavior.defaultTimeout ?? configuration.toolTimeout
                let result: ToolResultItem
                do {
                    let output = try await withTimeout(timeout, error: .toolTimedOut(call.name)) {
                        try await tool.invoke(context: toolContext, arguments: call.arguments)
                    }
                    result = ToolResultItem(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: output.content,
                        isError: false,
                        imagePaths: output.imagePaths
                    )
                } catch let error as AgentError {
                    result = ToolResultItem(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: error.localizedDescription,
                        isError: true
                    )
                } catch {
                    result = ToolResultItem(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: error.localizedDescription,
                        isError: true
                    )
                }
                allItems.append(.toolResult(result))
                newItems.append(.toolResult(result))
                events.yield(.toolCallCompleted(result))
            }
        }

        throw AgentError.maxTurnsExceeded(limit: configuration.maxTurns)
    }

    private func requestModel(
        _ request: ModelRequest,
        turn: Int,
        configuration: RunConfiguration,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> ModelResponse {
        var lastError: Error?
        for attempt in 1...configuration.retryPolicy.maximumAttempts {
            do {
                return try await withTimeout(configuration.modelTimeout, error: .modelTimedOut) {
                    var completed: ModelResponse?
                    for try await event in self.provider.streamResponse(request: request) {
                        try Task.checkCancellation()
                        switch event {
                        case .textDelta(let delta): events.yield(.textDelta(delta))
                        case .completed(let response): completed = response
                        }
                    }
                    guard let completed else {
                        throw AgentError.modelRequestFailed(.invalidResponse("模型流未返回完成事件"))
                    }
                    return completed
                }
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch {
                lastError = error
                if attempt < configuration.retryPolicy.maximumAttempts {
                    try await Task.sleep(for: configuration.retryPolicy.initialDelay)
                }
            }
        }
        if let error = lastError as? AgentError { throw error }
        throw AgentError.modelRequestFailed(.transport(lastError?.localizedDescription ?? "未知错误"))
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        error timeoutError: AgentError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw timeoutError
            }
            guard let first = try await group.next() else { throw timeoutError }
            group.cancelAll()
            return first
        }
    }

    private static func normalize(_ error: Error) -> AgentError {
        if let error = error as? AgentError { return error }
        if error is CancellationError { return .cancelled }
        return .modelRequestFailed(.transport(error.localizedDescription))
    }
}
