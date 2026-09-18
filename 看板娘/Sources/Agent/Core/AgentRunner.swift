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
    private let sessionCoordinator: AgentSessionRunCoordinator

    init(
        provider: any AgentModelProvider,
        sessionCoordinator: AgentSessionRunCoordinator = .shared
    ) {
        self.provider = provider
        self.sessionCoordinator = sessionCoordinator
    }

    func run<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration = RunConfiguration()
    ) -> AgentRun<Output> {
        let runID = UUID()
        return makeRun(runID: runID, sessionID: session.id) { events in
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
        makeRun(runID: state.runID, sessionID: session.id) { events in
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
        sessionID: String,
        operation: @escaping @Sendable (
            AsyncThrowingStream<AgentRunEvent, Error>.Continuation
        ) async throws -> RunResult<Output>
    ) -> AgentRun<Output> {
        let stream = AsyncThrowingStream<AgentRunEvent, Error>.makeStream()
        let task = Task<RunResult<Output>, Error> {
            guard await self.sessionCoordinator.acquire(sessionID: sessionID, runID: runID) else {
                let error = AgentError.busy
                stream.continuation.yield(.runFailed(error))
                stream.continuation.finish(throwing: error)
                throw error
            }
            do {
                let result = try await operation(stream.continuation)
                await self.sessionCoordinator.release(sessionID: sessionID, runID: runID)
                stream.continuation.finish()
                return result
            } catch {
                await self.sessionCoordinator.release(sessionID: sessionID, runID: runID)
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

        if try await loadRunState(from: session) != nil {
            throw AgentError.approvalStateInvalid
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
            knownInterruptionsByToolCallID: [:],
            approvalResolutionsByToolCallID: [:],
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
        guard let storedState = try await loadRunState(from: session),
              storedState.runID == state.runID,
              storedState.schemaVersion == state.schemaVersion else {
            throw AgentError.approvalStateInvalid
        }

        let interruptionsByID = Dictionary(
            uniqueKeysWithValues: state.interruptions.map { ($0.id, $0) }
        )
        var resolutions = state.approvalResolutionsByToolCallID
        for (interruptionID, decision) in decisions {
            guard let interruption = interruptionsByID[interruptionID] else {
                throw AgentError.approvalStateInvalid
            }
            resolutions[interruption.toolCall.id] = ApprovalResolution(
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
            knownInterruptionsByToolCallID: Dictionary(
                uniqueKeysWithValues: state.interruptions.map { ($0.toolCall.id, $0) }
            ),
            approvalResolutionsByToolCallID: resolutions,
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
        knownInterruptionsByToolCallID: [String: AgentInterruption],
        approvalResolutionsByToolCallID: [String: ApprovalResolution],
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
               knownInterruptionsByToolCallID: knownInterruptionsByToolCallID,
               approvalResolutionsByToolCallID: approvalResolutionsByToolCallID,
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
                interruptions: interruption.interruptions,
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
                knownInterruptionsByToolCallID: [:],
                approvalResolutionsByToolCallID: [:],
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
                    interruptions: interruption.interruptions,
                    state: interruption.state
                )
            }
        }

        throw AgentError.maxTurnsExceeded(limit: configuration.maxTurns)
    }

    private struct PendingInterruption: Sendable {
        let interruptions: [AgentInterruption]
        let state: RunState
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
        knownInterruptionsByToolCallID: [String: AgentInterruption],
        approvalResolutionsByToolCallID: [String: ApprovalResolution],
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> PendingInterruption? {
        var unresolved: [AgentInterruption] = []
        for call in calls {
            guard let tool = agent.tools.first(where: { $0.definition.name == call.name }) else {
                continue
            }
            let requiresApproval = try await tool.requiresApproval(arguments: call.arguments)
            guard requiresApproval,
                  approvalResolutionsByToolCallID[call.id] == nil else { continue }
            if let existing = knownInterruptionsByToolCallID[call.id] {
                unresolved.append(existing)
            } else {
                unresolved.append(AgentInterruption(
                    runID: runID,
                    toolCall: call,
                    summary: await tool.approvalSummary(arguments: call.arguments),
                    riskLevel: tool.behavior.riskLevel
                ))
            }
        }

        if !unresolved.isEmpty {
            let latestCompaction = allItems.reversed().compactMap { item -> CompactionItem? in
                guard case .compaction(let compaction) = item else { return nil }
                return compaction
            }.first
            let state = RunState(
                runID: runID,
                currentAgentID: agent.id,
                turn: turn,
                completedItems: allItems,
                pendingToolCalls: calls,
                interruptions: unresolved,
                approvalResolutionsByToolCallID: approvalResolutionsByToolCallID,
                contextCompaction: latestCompaction,
                providerContinuationID: providerContinuationID,
                rawResponses: rawResponses,
                usage: usage,
                traceID: traceID,
                sessionID: session.id
            )
            try await persistInterrupted(items: allItems, state: state, session: session)
            for interruption in unresolved { events.yield(.approvalRequired(interruption)) }
            return PendingInterruption(interruptions: unresolved, state: state)
        }

        var observationImages: [String] = []
        if canRunInParallel(calls, tools: agent.tools, configuration: configuration) {
            for call in calls { events.yield(.toolCallStarted(call)) }
            var indexedResults: [(Int, ToolResultItem)] = []
            let batchSize = min(configuration.maximumConcurrentTools, calls.count)
            var start = 0
            while start < calls.count {
                let end = min(start + batchSize, calls.count)
                let batch = Array(calls[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
                let results = await withTaskGroup(of: (Int, ToolResultItem).self) { group in
                    for (index, call) in batch {
                        let tool = agent.tools.first { $0.definition.name == call.name }!
                        group.addTask {
                            let result = await self.executeTool(
                                call,
                                tool: tool,
                                runID: runID,
                                agentID: agent.id,
                                sessionID: session.id,
                                context: context,
                                configuration: configuration
                            )
                            return (index, result)
                        }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
                indexedResults.append(contentsOf: results)
                start = end
            }
            for (_, result) in indexedResults.sorted(by: { $0.0 < $1.0 }) {
                observationImages.append(contentsOf: result.imagePaths)
                appendToolResult(result, allItems: &allItems, newItems: &newItems, events: events)
            }
        } else {
            for call in calls {
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

                if let resolvedDecision = approvalResolutionsByToolCallID[call.id] {
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
                let result = await executeTool(
                    call,
                    tool: tool,
                    runID: runID,
                    agentID: agent.id,
                    sessionID: session.id,
                    context: context,
                    configuration: configuration
                )
                observationImages.append(contentsOf: result.imagePaths)
                appendToolResult(result, allItems: &allItems, newItems: &newItems, events: events)
            }
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

    private func canRunInParallel<Context: Sendable>(
        _ calls: [ToolCallItem],
        tools: [AnyAgentTool<Context>],
        configuration: RunConfiguration
    ) -> Bool {
        guard calls.count > 1,
              configuration.maximumConcurrentTools > 1,
              provider.capabilities.supportsParallelTools else { return false }
        return calls.allSatisfy { call in
            guard let tool = tools.first(where: { $0.definition.name == call.name }) else {
                return false
            }
            return tool.behavior.allowsParallelExecution
                && tool.behavior.isReadOnly
                && tool.behavior.isIdempotent
                && !tool.behavior.hasExternalSideEffects
                && !tool.behavior.requiresApproval
        }
    }

    private func executeTool<Context: Sendable>(
        _ call: ToolCallItem,
        tool: AnyAgentTool<Context>,
        runID: UUID,
        agentID: String,
        sessionID: String,
        context: Context,
        configuration: RunConfiguration
    ) async -> ToolResultItem {
        let attempts = tool.behavior.isIdempotent && tool.behavior.allowsAutomaticRetry
            ? configuration.retryPolicy.maximumAttempts
            : 1
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let output = try await withTimeout(
                    tool.behavior.defaultTimeout ?? configuration.toolTimeout,
                    error: .toolTimedOut(call.name)
                ) {
                    try await tool.invoke(
                        context: ToolContext(
                            runID: runID,
                            sessionID: sessionID,
                            agentID: agentID,
                            context: context
                        ),
                        arguments: call.arguments
                    )
                }
                return ToolResultItem(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: output.content,
                    isError: false,
                    imagePaths: output.imagePaths
                )
            } catch is CancellationError {
                lastError = AgentError.cancelled
                break
            } catch {
                lastError = error
                if attempt < attempts {
                    do {
                        try await Task.sleep(for: configuration.retryPolicy.initialDelay)
                    } catch {
                        lastError = AgentError.cancelled
                        break
                    }
                }
            }
        }
        let detail = (lastError as? LocalizedError)?.errorDescription
            ?? lastError?.localizedDescription
            ?? "未知错误"
        return ToolResultItem(
            toolCallID: call.id,
            toolName: call.name,
            content: detail,
            isError: true
        )
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

    private func loadRunState(from session: any AgentSession) async throws -> RunState? {
        do { return try await session.loadRunState() }
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
        interruptions: [AgentInterruption],
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
            interruptions: interruptions,
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
