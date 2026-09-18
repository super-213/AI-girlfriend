import Foundation

struct AgentInput: Sendable, Equatable {
    let text: String
    let imagePaths: [String]
    let followingItems: [AgentItem]

    init(
        _ text: String,
        imagePaths: [String] = [],
        followingItems: [AgentItem] = []
    ) {
        self.text = text
        self.imagePaths = imagePaths
        self.followingItems = followingItems
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

/// Executes one user turn without depending on a concrete UI or model provider.
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
        return makeRun(runID: runID) { events in
            try await self.executeNewRun(
                runID: runID,
                agent: agent,
                input: input,
                context: context,
                session: session,
                configuration: configuration,
                events: events
            )
        }
    }

    /// Resumes the same interrupted run. Decisions are keyed by interruption ID.
    func resume<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        from state: RunState,
        decisions: [UUID: ApprovalDecision],
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration = RunConfiguration()
    ) -> AgentRun<Output> {
        makeRun(runID: state.runID) { events in
            try await self.executeResumedRun(
                agent: agent,
                state: state,
                decisions: decisions,
                context: context,
                session: session,
                configuration: configuration,
                events: events
            )
        }
    }

    private func makeRun<Output: Sendable>(
        runID: UUID,
        operation: @escaping @Sendable (
            AsyncThrowingStream<AgentRunEvent, Error>.Continuation
        ) async throws -> RunResult<Output>
    ) -> AgentRun<Output> {
        let stream = AsyncThrowingStream<AgentRunEvent, Error>.makeStream()
        let task = Task<RunResult<Output>, Error> {
            do {
                let result = try await operation(stream.continuation)
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

    private func executeNewRun<Context: Sendable, Output: Sendable>(
        runID: UUID,
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> RunResult<Output> {
        try validate(agent: agent, configuration: configuration)
        let trimmedInput = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw AgentError.invalidConfiguration("输入不能为空")
        }

        var allItems = try await loadItems(from: session)
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
        newItems.append(contentsOf: input.followingItems)
        allItems.append(contentsOf: newItems)

        let traceID = UUID()
        emitStart(runID: runID, sessionID: session.id, agent: agent, events: events)
        return try await continueExecution(
            runID: runID,
            traceID: traceID,
            agent: agent,
            context: context,
            session: session,
            configuration: configuration,
            completedTurnCount: 0,
            allItems: allItems,
            newItems: newItems,
            pendingCalls: [],
            decisionsByToolCallID: [:],
            rawResponses: [],
            usage: .zero,
            events: events
        )
    }

    private func executeResumedRun<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        state: RunState,
        decisions: [UUID: ApprovalDecision],
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> RunResult<Output> {
        try validate(agent: agent, configuration: configuration)
        guard state.schemaVersion == RunState.currentSchemaVersion,
              state.sessionID == session.id,
              state.currentAgentID == agent.id,
              !state.interruptions.isEmpty else {
            throw AgentError.approvalStateInvalid
        }

        var decisionsByToolCallID: [String: ResolvedApprovalDecision] = [:]
        for interruption in state.interruptions {
            guard let decision = decisions[interruption.id] else {
                throw AgentError.approvalStateInvalid
            }
            decisionsByToolCallID[interruption.toolCall.id] = ResolvedApprovalDecision(
                interruptionID: interruption.id,
                decision: decision
            )
        }

        emitStart(runID: state.runID, sessionID: session.id, agent: agent, events: events)
        return try await continueExecution(
            runID: state.runID,
            traceID: state.traceID,
            agent: agent,
            context: context,
            session: session,
            configuration: configuration,
            completedTurnCount: state.turn,
            allItems: state.completedItems,
            newItems: [],
            pendingCalls: state.pendingToolCalls,
            decisionsByToolCallID: decisionsByToolCallID,
            rawResponses: state.rawResponses,
            usage: state.usage,
            events: events
        )
    }

    private func continueExecution<Context: Sendable, Output: Sendable>(
        runID: UUID,
        traceID: UUID,
        agent: AgentDefinition<Context, Output>,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        completedTurnCount: Int,
        allItems initialItems: [AgentItem],
        newItems initialNewItems: [AgentItem],
        pendingCalls: [ToolCallItem],
        decisionsByToolCallID: [String: ResolvedApprovalDecision],
        rawResponses initialResponses: [ModelResponse],
        usage initialUsage: AgentUsage,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> RunResult<Output> {
        var allItems = initialItems
        var newItems = initialNewItems
        var rawResponses = initialResponses
        var usage = initialUsage
        var turnCount = completedTurnCount

        if !pendingCalls.isEmpty,
           let interruption = try await processToolCalls(
               pendingCalls,
               runID: runID,
               traceID: traceID,
               agent: agent,
               context: context,
               session: session,
               configuration: configuration,
               turn: turnCount,
               providerContinuationID: nil,
               rawResponses: rawResponses,
               usage: usage,
               decisionsByToolCallID: decisionsByToolCallID,
               allItems: &allItems,
               newItems: &newItems,
               events: events
           ) {
            return interruptedResult(
                runID: runID,
                agentID: agent.id,
                allItems: allItems,
                newItems: newItems,
                usage: usage,
                rawResponses: rawResponses,
                interruption: interruption.interruption,
                state: interruption.state
            )
        }

        while turnCount < configuration.maxTurns {
            try Task.checkCancellation()
            turnCount += 1
            events.yield(.modelStarted(ModelRequestSnapshot(
                turn: turnCount,
                providerID: agent.model.providerID,
                modelID: agent.model.modelID
            )))
            let response = try await requestModel(
                ModelRequest(
                    runID: runID,
                    agentID: agent.id,
                    model: agent.model,
                    items: allItems,
                    tools: agent.tools.map(\.definition)
                ),
                configuration: configuration,
                events: events
            )
            rawResponses.append(response)
            usage.add(response.usage)
            events.yield(.modelCompleted(ModelResponseSnapshot(turn: turnCount, response: response)))
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

            guard !response.toolCalls.isEmpty else {
                let output = try decode(response.content, using: agent.outputDecoder)
                try await persistCompleted(items: allItems, session: session)
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

            if let interruption = try await processToolCalls(
                response.toolCalls,
                runID: runID,
                traceID: traceID,
                agent: agent,
                context: context,
                session: session,
                configuration: configuration,
                turn: turnCount,
                providerContinuationID: response.id,
                rawResponses: rawResponses,
                usage: usage,
                decisionsByToolCallID: [:],
                allItems: &allItems,
                newItems: &newItems,
                events: events
            ) {
                return interruptedResult(
                    runID: runID,
                    agentID: agent.id,
                    allItems: allItems,
                    newItems: newItems,
                    usage: usage,
                    rawResponses: rawResponses,
                    interruption: interruption.interruption,
                    state: interruption.state
                )
            }
        }

        throw AgentError.maxTurnsExceeded(limit: configuration.maxTurns)
    }

    private struct PendingInterruption: Sendable {
        let interruption: AgentInterruption
        let state: RunState
    }

    private struct ResolvedApprovalDecision: Sendable {
        let interruptionID: UUID
        let decision: ApprovalDecision
    }

    private func processToolCalls<Context: Sendable, Output: Sendable>(
        _ calls: [ToolCallItem],
        runID: UUID,
        traceID: UUID,
        agent: AgentDefinition<Context, Output>,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        turn: Int,
        providerContinuationID: String?,
        rawResponses: [ModelResponse],
        usage: AgentUsage,
        decisionsByToolCallID: [String: ResolvedApprovalDecision],
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> PendingInterruption? {
        var observationImages: [String] = []
        for (index, call) in calls.enumerated() {
            guard let tool = agent.tools.first(where: { $0.definition.name == call.name }) else {
                appendToolResult(
                    ToolResultItem(
                        toolCallID: call.id,
                        toolName: call.name,
                        content: AgentError.toolUnavailable(call.name).localizedDescription,
                        isError: true
                    ),
                    allItems: &allItems,
                    newItems: &newItems,
                    events: events
                )
                continue
            }

            let requiresApproval = try await tool.requiresApproval(arguments: call.arguments)
            if requiresApproval, decisionsByToolCallID[call.id] == nil {
                let interruption = AgentInterruption(
                    runID: runID,
                    toolCall: call,
                    summary: await tool.approvalSummary(arguments: call.arguments),
                    riskLevel: tool.behavior.riskLevel
                )
                let state = RunState(
                    runID: runID,
                    currentAgentID: agent.id,
                    turn: turn,
                    completedItems: allItems,
                    pendingToolCalls: Array(calls[index...]),
                    interruptions: [interruption],
                    providerContinuationID: providerContinuationID,
                    rawResponses: rawResponses,
                    usage: usage,
                    traceID: traceID,
                    sessionID: session.id
                )
                try await persistInterrupted(items: allItems, state: state, session: session)
                events.yield(.approvalRequired(interruption))
                return PendingInterruption(interruption: interruption, state: state)
            }

            if let resolvedDecision = decisionsByToolCallID[call.id] {
                let approval = AgentItem.approval(ApprovalItem(
                    interruptionID: resolvedDecision.interruptionID,
                    decision: resolvedDecision.decision
                ))
                allItems.append(approval)
                newItems.append(approval)
                if case .rejected(let reason) = resolvedDecision.decision {
                    appendToolResult(
                        ToolResultItem(
                            toolCallID: call.id,
                            toolName: call.name,
                            content: reason ?? "用户拒绝执行该工具",
                            isError: true
                        ),
                        allItems: &allItems,
                        newItems: &newItems,
                        events: events
                    )
                    continue
                }
            }

            events.yield(.toolCallStarted(call))
            let result: ToolResultItem
            do {
                let output = try await withTimeout(
                    tool.behavior.defaultTimeout ?? configuration.toolTimeout,
                    error: .toolTimedOut(call.name)
                ) {
                    try await tool.invoke(
                        context: ToolContext(
                            runID: runID,
                            sessionID: session.id,
                            agentID: agent.id,
                            context: context
                        ),
                        arguments: call.arguments
                    )
                }
                observationImages.append(contentsOf: output.imagePaths)
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
            appendToolResult(result, allItems: &allItems, newItems: &newItems, events: events)
        }

        if !observationImages.isEmpty {
            let observation = AgentItem.message(AgentMessageItem(
                role: .user,
                content: "以下图像是桌面观察工具在上一步操作后捕获的最新界面。请结合工具返回继续判断下一步。",
                imagePaths: observationImages,
                contextKind: .desktopObservation
            ))
            allItems.append(observation)
            newItems.append(observation)
        }
        return nil
    }

    private func requestModel(
        _ request: ModelRequest,
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

    private func validate<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        configuration: RunConfiguration
    ) throws {
        try configuration.validate()
        try Task.checkCancellation()
        guard agent.tools.isEmpty || provider.capabilities.supportsTools else {
            throw AgentError.modelRequestFailed(.unsupportedCapability("当前 Provider 不支持工具调用"))
        }
    }

    private func emitStart<Context: Sendable, Output: Sendable>(
        runID: UUID,
        sessionID: String,
        agent: AgentDefinition<Context, Output>,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) {
        events.yield(.runStarted(RunSnapshot(runID: runID, sessionID: sessionID, startedAt: .now)))
        events.yield(.agentStarted(AgentSnapshot(id: agent.id, name: agent.name)))
    }

    private func loadItems(from session: any AgentSession) async throws -> [AgentItem] {
        do { return try await session.loadItems() }
        catch { throw AgentError.sessionFailure(error.localizedDescription) }
    }

    private func persistCompleted(items: [AgentItem], session: any AgentSession) async throws {
        do {
            try await session.replaceItems(items)
            try await session.saveRunState(nil)
        } catch {
            throw AgentError.sessionFailure(error.localizedDescription)
        }
    }

    private func persistInterrupted(
        items: [AgentItem],
        state: RunState,
        session: any AgentSession
    ) async throws {
        do {
            try await session.replaceItems(items)
            try await session.saveRunState(state)
        } catch {
            throw AgentError.sessionFailure(error.localizedDescription)
        }
    }

    private func decode<Output: Sendable>(
        _ content: String,
        using decoder: AgentOutputDecoder<Output>
    ) throws -> Output {
        do { return try decoder.decode(content) }
        catch let error as AgentError { throw error }
        catch { throw AgentError.outputValidationFailed(error.localizedDescription) }
    }

    private func interruptedResult<Output: Sendable>(
        runID: UUID,
        agentID: String,
        allItems: [AgentItem],
        newItems: [AgentItem],
        usage: AgentUsage,
        rawResponses: [ModelResponse],
        interruption: AgentInterruption,
        state: RunState
    ) -> RunResult<Output> {
        RunResult(
            runID: runID,
            finalOutput: nil,
            history: allItems,
            newItems: newItems,
            lastAgentID: agentID,
            usage: usage,
            rawResponses: rawResponses,
            guardrailResults: [],
            interruptions: [interruption],
            resumableState: state
        )
    }

    private func appendToolResult(
        _ result: ToolResultItem,
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) {
        let item = AgentItem.toolResult(result)
        allItems.append(item)
        newItems.append(item)
        events.yield(.toolCallCompleted(result))
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
