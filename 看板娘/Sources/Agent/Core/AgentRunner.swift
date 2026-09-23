import Foundation

struct AgentInput: Sendable, Equatable {
    let text: String
    let imagePaths: [String]
    let followingItems: [AgentItem]
    let preflightToolCalls: [ToolCallItem]

    init(
        _ text: String,
        imagePaths: [String] = [],
        followingItems: [AgentItem] = [],
        preflightToolCalls: [ToolCallItem] = []
    ) {
        self.text = text
        self.imagePaths = imagePaths
        self.followingItems = followingItems
        self.preflightToolCalls = preflightToolCalls
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
    private let tracer: any AgentTracer

    init(
        provider: any AgentModelProvider,
        sessionCoordinator: AgentSessionRunCoordinator = .shared,
        tracer: any AgentTracer = LocalAgentTracer.shared
    ) {
        self.provider = provider
        self.sessionCoordinator = sessionCoordinator
        self.tracer = tracer
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
                parentTrace: nil,
                events: events
            )
        }
    }

    func runNested<Context: Sendable, Output: Sendable>(
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration = RunConfiguration(),
        parentTrace: AgentTraceContext?
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
                parentTrace: parentTrace,
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
        parentTrace: AgentTraceContext?,
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
        let startingAgent = lastResponsibleAgentID(in: allItems)
            .flatMap { agent.resolvingAgent(id: $0) } ?? agent
        try validate(agent: startingAgent, configuration: configuration)
        var newItems: [AgentItem] = []
        var guardrailResults: [GuardrailResult] = []
        let traceID = parentTrace?.traceID ?? UUID()
        let trace = AgentRunTrace(
            tracer: tracer,
            enabled: configuration.tracingEnabled,
            traceID: traceID,
            runID: runID,
            sessionID: session.id,
            agentID: startingAgent.id
        )
        await trace.start(
            agentID: startingAgent.id,
            agentName: startingAgent.name,
            parentSpanID: parentTrace?.parentSpanID
        )
        emitStart(runID: runID, sessionID: session.id, agent: startingAgent, events: events)
        let guardrailContext = AgentGuardrailContext(
            runID: runID,
            sessionID: session.id,
            agentID: startingAgent.id,
            context: context
        )
        do {
            for guardrail in startingAgent.inputGuardrails {
                let result = await evaluateInputGuardrail(
                    guardrail,
                    context: guardrailContext,
                    input: input,
                    trace: trace
                )
                guardrailResults.append(result)
                events.yield(.guardrailEvaluated(result))
                guard result.action == .allow else {
                    throw AgentError.guardrailTriggered(result)
                }
            }
            if let compaction = allItems.reversed().compactMap({ item -> CompactionItem? in
                guard case .compaction(let value) = item else { return nil }
                return value
            }).first {
                await traceCompaction(compaction, trace: trace)
            }
            let instructions = try await startingAgent.instructions.resolve(using: context)
            if let systemIndex = allItems.firstIndex(where: {
                if case .message(let message) = $0 {
                    return message.role == .system && message.contextKind == nil
                }
                return false
            }) {
                allItems[systemIndex] = .message(AgentMessageItem(
                    role: .system,
                    content: instructions
                ))
            } else {
                newItems.append(.message(AgentMessageItem(role: .system, content: instructions)))
            }
            newItems.append(.message(AgentMessageItem(
                role: .user,
                content: trimmedInput,
                imagePaths: input.imagePaths
            )))
            newItems.append(contentsOf: input.followingItems)
            if !input.preflightToolCalls.isEmpty {
                let assistant = AgentItem.message(AgentMessageItem(role: .assistant, content: nil))
                newItems.append(assistant)
                newItems.append(contentsOf: input.preflightToolCalls.map(AgentItem.toolCall))
            }
            newItems.append(contentsOf: guardrailResults.map { .guardrail(GuardrailItem(result: $0)) })
            allItems.append(contentsOf: newItems)

            try await compactHistoryIfNeeded(
                runID: runID,
                agentID: startingAgent.id,
                model: startingAgent.model,
                tools: startingAgent.tools.map(\.definition),
                policy: configuration.contextCompactionPolicy,
                force: configuration.forceContextCompaction,
                configuration: configuration,
                trace: trace,
                allItems: &allItems,
                newItems: &newItems,
                events: events
            )

            let result = try await continueExecution(
                runID: runID,
                traceID: traceID,
                trace: trace,
                agent: startingAgent,
                context: context,
                session: session,
                configuration: configuration,
                completedTurnCount: 0,
                allItems: allItems,
                newItems: newItems,
                pendingCalls: input.preflightToolCalls,
                knownInterruptionsByToolCallID: [:],
                approvalResolutionsByToolCallID: [:],
                rawResponses: [],
                usage: .zero,
                guardrailResults: guardrailResults,
                events: events
            )
            await trace.finish(
                status: result.resumableState == nil ? .completed : .interrupted,
                usage: result.usage
            )
            return result
        } catch {
            await trace.finish(
                status: error is CancellationError || error as? AgentError == .cancelled
                    ? .cancelled : .failed,
                error: error
            )
            throw error
        }
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
        guard let activeAgent = agent.resolvingAgent(id: state.currentAgentID) else {
            throw AgentError.approvalStateInvalid
        }
        try validate(agent: activeAgent, configuration: configuration)
        guard state.schemaVersion == RunState.currentSchemaVersion,
              state.sessionID == session.id,
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

        let trace = AgentRunTrace(
            tracer: tracer,
            enabled: configuration.tracingEnabled,
            traceID: state.traceID,
            runID: state.runID,
            sessionID: session.id,
            agentID: activeAgent.id
        )
        await trace.start(agentID: activeAgent.id, agentName: activeAgent.name)
        for (interruptionID, decision) in decisions {
            guard let interruption = interruptionsByID[interruptionID] else { continue }
            await traceApprovalDecision(interruption, decision: decision, trace: trace)
        }
        emitStart(runID: state.runID, sessionID: session.id, agent: activeAgent, events: events)
        do {
            let result = try await continueExecution(
                runID: state.runID,
                traceID: state.traceID,
                trace: trace,
                agent: activeAgent,
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
                guardrailResults: state.guardrailResults,
                events: events
            )
            await trace.finish(
                status: result.resumableState == nil ? .completed : .interrupted,
                usage: result.usage
            )
            return result
        } catch {
            await trace.finish(
                status: error is CancellationError || error as? AgentError == .cancelled
                    ? .cancelled : .failed,
                error: error
            )
            throw error
        }
    }

    private func continueExecution<Context: Sendable, Output: Sendable>(
        runID: UUID,
        traceID: UUID,
        trace: AgentRunTrace,
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
        guardrailResults initialGuardrailResults: [GuardrailResult],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> RunResult<Output> {
        var currentAgent = agent
        var allItems = initialItems
        var newItems = initialNewItems
        var rawResponses = initialResponses
        var usage = initialUsage
        var guardrailResults = initialGuardrailResults
        var turnCount = completedTurnCount

        if !pendingCalls.isEmpty,
           let interruption = try await processToolCalls(
               pendingCalls,
               runID: runID,
               traceID: traceID,
               trace: trace,
               agent: currentAgent,
               context: context,
               session: session,
               configuration: configuration,
               turn: turnCount,
               providerContinuationID: nil,
               rawResponses: rawResponses,
               usage: usage,
               guardrailResults: &guardrailResults,
               knownInterruptionsByToolCallID: knownInterruptionsByToolCallID,
               approvalResolutionsByToolCallID: approvalResolutionsByToolCallID,
               allItems: &allItems,
               newItems: &newItems,
               events: events
           ) {
            return interruptedResult(
                runID: runID,
                agentID: currentAgent.id,
                allItems: allItems,
                newItems: newItems,
                usage: usage,
                rawResponses: rawResponses,
                guardrailResults: guardrailResults,
                interruptions: interruption.interruptions,
                state: interruption.state
            )
        }

        while turnCount < configuration.maxTurns {
            try Task.checkCancellation()
            turnCount += 1
            events.yield(.modelStarted(ModelRequestSnapshot(
                turn: turnCount,
                providerID: currentAgent.model.providerID,
                modelID: currentAgent.model.modelID
            )))
            let modelSpan = await trace.startChild(
                kind: .model,
                name: "model.request",
                agentID: currentAgent.id,
                providerID: currentAgent.model.providerID,
                modelID: currentAgent.model.modelID,
                attributes: ["turn": String(turnCount)]
            )
            let guardrailContext = AgentGuardrailContext(
                runID: runID,
                sessionID: session.id,
                agentID: currentAgent.id,
                context: context
            )
            let modelResult: ModelStreamResult
            do {
                modelResult = try await requestModel(
                    ModelRequest(
                        runID: runID,
                        agentID: currentAgent.id,
                        model: currentAgent.model,
                        items: allItems,
                        tools: currentAgent.tools.map(\.definition)
                            + currentAgent.handoffs.map(\.toolDefinition),
                        outputSchema: currentAgent.outputSchema
                    ),
                    configuration: configuration,
                    trace: trace,
                    span: modelSpan,
                    events: events,
                    outputGuardrails: currentAgent.outputGuardrails,
                    guardrailContext: guardrailContext
                )
                let response = modelResult.response
                if let usage = response.usage { await trace.record(.usage(usage), in: modelSpan) }
                await trace.end(
                    modelSpan,
                    outcome: SpanOutcome(status: .completed, usage: response.usage)
                )
            } catch {
                await trace.end(modelSpan, outcome: SpanOutcome(status: .failed, error: error))
                throw error
            }
            let response = modelResult.response
            rawResponses.append(response)
            usage.add(response.usage)
            events.yield(.modelCompleted(ModelResponseSnapshot(turn: turnCount, response: response)))
            if response.usage != nil { events.yield(.usageUpdated(usage)) }

            if !response.responseOutput.isEmpty {
                let output = AgentItem.responseOutput(response.responseOutput)
                allItems.append(output)
                newItems.append(output)
            }

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

            if let target = try await performHandoffIfRequested(
                response.toolCalls,
                from: currentAgent,
                context: context,
                trace: trace,
                allItems: &allItems,
                newItems: &newItems,
                events: events
            ) {
                currentAgent = target
                try validate(agent: currentAgent, configuration: configuration)
                continue
            }

            guard !response.toolCalls.isEmpty else {
                let output = try decode(response.content, using: currentAgent.outputDecoder)
                for guardrail in currentAgent.outputGuardrails {
                    let result = await evaluateOutputGuardrail(
                        guardrail,
                        context: guardrailContext,
                        output: output,
                        trace: trace
                    )
                    guardrailResults.append(result)
                    events.yield(.guardrailEvaluated(result))
                    let item = AgentItem.guardrail(GuardrailItem(result: result))
                    allItems.append(item)
                    newItems.append(item)
                    guard result.action == .allow else {
                        throw AgentError.guardrailTriggered(result)
                    }
                }
                if !modelResult.didStreamText, !response.content.isEmpty {
                    events.yield(.textDelta(response.content))
                }
                try await persistCompleted(items: allItems, session: session)
                events.yield(.runCompleted)
                return RunResult(
                    runID: runID,
                    finalOutput: output,
                    history: allItems,
                    newItems: newItems,
                    lastAgentID: currentAgent.id,
                    usage: usage,
                    rawResponses: rawResponses,
                    guardrailResults: guardrailResults,
                    interruptions: [],
                    resumableState: nil
                )
            }

            if let interruption = try await processToolCalls(
                response.toolCalls,
                runID: runID,
                traceID: traceID,
                trace: trace,
                agent: currentAgent,
                context: context,
                session: session,
                configuration: configuration,
                turn: turnCount,
                providerContinuationID: response.id,
                rawResponses: rawResponses,
                usage: usage,
                guardrailResults: &guardrailResults,
                knownInterruptionsByToolCallID: [:],
                approvalResolutionsByToolCallID: [:],
                allItems: &allItems,
                newItems: &newItems,
                events: events
            ) {
                return interruptedResult(
                    runID: runID,
                    agentID: currentAgent.id,
                    allItems: allItems,
                    newItems: newItems,
                    usage: usage,
                    rawResponses: rawResponses,
                    guardrailResults: guardrailResults,
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
        trace: AgentRunTrace,
        agent: AgentDefinition<Context, Output>,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration,
        turn: Int,
        providerContinuationID: String?,
        rawResponses: [ModelResponse],
        usage: AgentUsage,
        guardrailResults: inout [GuardrailResult],
        knownInterruptionsByToolCallID: [String: AgentInterruption],
        approvalResolutionsByToolCallID: [String: ApprovalResolution],
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> PendingInterruption? {
        var unresolved: [AgentInterruption] = []
        var guardrailApprovalSummaries: [String: String] = [:]
        let guardrailContext = AgentGuardrailContext(
            runID: runID,
            sessionID: session.id,
            agentID: agent.id,
            context: context
        )
        for call in calls {
            guard let tool = agent.tools.first(where: { $0.definition.name == call.name }) else {
                continue
            }
            var requiresApproval = try await tool.requiresApproval(arguments: call.arguments)
            for guardrail in agent.toolGuardrails {
                let result = await evaluateToolInputGuardrail(
                    guardrail,
                    context: guardrailContext,
                    call: call,
                    tool: tool.definition,
                    trace: trace
                )
                guardrailResults.append(result)
                events.yield(.guardrailEvaluated(result))
                let item = AgentItem.guardrail(GuardrailItem(result: result))
                allItems.append(item)
                newItems.append(item)
                switch result.action {
                case .allow:
                    break
                case .stop:
                    throw AgentError.guardrailTriggered(result)
                case .requireApproval:
                    requiresApproval = true
                    guardrailApprovalSummaries[call.id] = result.message
                }
            }
            guard requiresApproval,
                  approvalResolutionsByToolCallID[call.id] == nil else { continue }
            if let existing = knownInterruptionsByToolCallID[call.id] {
                unresolved.append(existing)
            } else {
                let summary: String
                if let guardrailSummary = guardrailApprovalSummaries[call.id] {
                    summary = guardrailSummary
                } else {
                    summary = await tool.approvalSummary(arguments: call.arguments)
                }
                unresolved.append(AgentInterruption(
                    runID: runID,
                    toolCall: call,
                    summary: summary,
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
                guardrailResults: guardrailResults,
                traceID: traceID,
                sessionID: session.id
            )
            try await persistInterrupted(items: allItems, state: state, session: session)
            for interruption in unresolved {
                await traceApprovalRequest(interruption, trace: trace)
                events.yield(.approvalRequired(interruption))
            }
            return PendingInterruption(interruptions: unresolved, state: state)
        }

        var rejectionReasons: [String: String] = [:]
        for call in calls {
            guard let resolution = approvalResolutionsByToolCallID[call.id] else { continue }
            let approval = AgentItem.approval(ApprovalItem(
                interruptionID: resolution.interruptionID,
                decision: resolution.decision
            ))
            allItems.append(approval)
            newItems.append(approval)
            if case .rejected(let reason) = resolution.decision {
                rejectionReasons[call.id] = reason ?? "用户拒绝执行该工具"
            }
        }
        let executableCalls = calls.filter { rejectionReasons[$0.id] == nil }
        var observationImages: [String] = []
        if canRunInParallel(executableCalls, tools: agent.tools, configuration: configuration) {
            for call in executableCalls { events.yield(.toolCallStarted(call)) }
            var indexedResults: [(Int, ToolResultItem)] = []
            let batchSize = min(configuration.maximumConcurrentTools, executableCalls.count)
            var start = 0
            while start < executableCalls.count {
                let end = min(start + batchSize, executableCalls.count)
                let batch = Array(executableCalls[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
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
                                configuration: configuration,
                                trace: trace
                            )
                            return (index, result)
                        }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
                indexedResults.append(contentsOf: results)
                start = end
            }
            let orderedResults = indexedResults.sorted(by: { $0.0 < $1.0 }).map(\.1)
            var resultIndex = 0
            for call in calls {
                if let reason = rejectionReasons[call.id] {
                    appendToolResult(
                        ToolResultItem(
                            toolCallID: call.id,
                            toolName: call.name,
                            content: reason,
                            isError: true
                        ),
                        allItems: &allItems,
                        newItems: &newItems,
                        events: events
                    )
                    continue
                }
                let result = orderedResults[resultIndex]
                resultIndex += 1
                try await applyToolOutputGuardrails(
                    agent.toolGuardrails,
                    context: guardrailContext,
                    call: call,
                    result: result,
                    guardrailResults: &guardrailResults,
                    allItems: &allItems,
                    newItems: &newItems,
                    trace: trace,
                    events: events
                )
                observationImages.append(contentsOf: result.imagePaths)
                appendToolResult(result, allItems: &allItems, newItems: &newItems, events: events)
            }
        } else {
            for call in calls {
                if let reason = rejectionReasons[call.id] {
                    appendToolResult(
                        ToolResultItem(
                            toolCallID: call.id,
                            toolName: call.name,
                            content: reason,
                            isError: true
                        ),
                        allItems: &allItems,
                        newItems: &newItems,
                        events: events
                    )
                    continue
                }
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

                events.yield(.toolCallStarted(call))
                let result = await executeTool(
                    call,
                    tool: tool,
                    runID: runID,
                    agentID: agent.id,
                    sessionID: session.id,
                    context: context,
                    configuration: configuration,
                    trace: trace
                )
                try await applyToolOutputGuardrails(
                    agent.toolGuardrails,
                    context: guardrailContext,
                    call: call,
                    result: result,
                    guardrailResults: &guardrailResults,
                    allItems: &allItems,
                    newItems: &newItems,
                    trace: trace,
                    events: events
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

        if calls.contains(where: { $0.name == AgentRuntimeToolName.compactContext }) {
            try await compactHistoryIfNeeded(
                runID: runID,
                agentID: agent.id,
                model: agent.model,
                tools: agent.tools.map(\.definition),
                policy: configuration.contextCompactionPolicy ?? .standard,
                force: true,
                configuration: configuration,
                trace: trace,
                allItems: &allItems,
                newItems: &newItems,
                events: events
            )
        }
        return nil
    }

    private func compactHistoryIfNeeded(
        runID: UUID,
        agentID: String,
        model: AgentModelConfiguration,
        tools: [ToolDefinition],
        policy: AgentContextCompactionPolicy?,
        force: Bool,
        configuration: RunConfiguration,
        trace: AgentRunTrace,
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws {
        guard let policy else { return }
        let manager = AgentContextManager(policy: policy)
        let messages = AgentItemLegacyCodec.messages(from: allItems)
        let legacyTools = tools.map {
            AgentToolDefinition(
                name: $0.name,
                description: $0.description,
                parameters: $0.parameters.foundationValue as? [String: Any] ?? [:]
            )
        }
        guard let plan = manager.makePlan(
            messages: messages,
            tools: legacyTools,
            force: force
        ), let system = messages.first(where: { $0.role == .system && $0.contextKind == nil }) else {
            return
        }

        events.yield(.contextCompactionStarted)
        let compactionSpan = await trace.startChild(
            kind: .compaction,
            name: "context.compaction",
            agentID: agentID,
            attributes: ["summarized_items": String(plan.messagesToSummarize.count)]
        )
        let modelSpan = await trace.startChild(
            kind: .model,
            name: "context.compaction.model",
            agentID: agentID,
            parentSpanID: compactionSpan?.spanID,
            providerID: model.providerID,
            modelID: model.modelID
        )
        do {
            let modelResult = try await requestModel(
                ModelRequest(
                    runID: runID,
                    agentID: agentID,
                    model: model,
                    items: AgentItemLegacyCodec.items(from: manager.summaryRequestMessages(for: plan)),
                    tools: [],
                    purpose: .contextCompaction
                ),
                configuration: configuration,
                trace: trace,
                span: modelSpan,
                events: events,
                outputGuardrails: [AnyOutputGuardrail<Void, String>](),
                guardrailContext: nil,
                emitTextDeltas: false
            )
            let response = modelResult.response
            guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentError.modelRequestFailed(.invalidResponse("上下文压缩返回空摘要"))
            }
            await trace.end(
                modelSpan,
                outcome: SpanOutcome(status: .completed, usage: response.usage)
            )
            let compactedMessages = manager.compactedMessages(
                systemMessage: system,
                summary: response.content,
                plan: plan
            )
            let compaction = CompactionItem(
                summary: response.content,
                summarizedItemCount: plan.messagesToSummarize.count
            )
            let structuralItems = allItems.filter { item in
                switch item {
                case .handoff, .guardrail, .approval:
                    return true
                case .message, .responseOutput, .toolCall, .toolResult, .compaction:
                    return false
                }
            }
            allItems = AgentItemLegacyCodec.items(from: compactedMessages).map { item in
                if case .compaction = item { return .compaction(compaction) }
                return item
            } + structuralItems
            newItems.append(.compaction(compaction))
            let event = CompactionEvent(
                summarizedItemCount: plan.messagesToSummarize.count,
                retainedItemCount: plan.recentMessages.count,
                estimatedTokensBeforeCompaction: plan.estimatedTokensBeforeCompaction
            )
            events.yield(.contextCompacted(event))
            await trace.end(compactionSpan, outcome: SpanOutcome(status: .completed, usage: response.usage))
        } catch {
            await trace.end(modelSpan, outcome: SpanOutcome(status: .failed, error: error))
            await trace.end(compactionSpan, outcome: SpanOutcome(status: .failed, error: error))
            throw error
        }
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
        configuration: RunConfiguration,
        trace: AgentRunTrace
    ) async -> ToolResultItem {
        let toolSpan = await trace.startChild(
            kind: .tool,
            name: call.name,
            agentID: agentID,
            attributes: [
                "tool.name": call.name,
                "tool.call_id": call.id,
                "tool.arguments": TraceRedactor.toolArguments(call.arguments),
                "summary": "执行工具 \(call.name)"
            ]
        )
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
                            context: context,
                            traceContext: toolSpan.map {
                                AgentTraceContext(traceID: $0.traceID, parentSpanID: $0.spanID)
                            }
                        ),
                        arguments: call.arguments
                    )
                }
                let result = ToolResultItem(
                    toolCallID: call.id,
                    toolName: call.name,
                    content: output.content,
                    isError: false,
                    imagePaths: output.imagePaths
                )
                await trace.end(
                    toolSpan,
                    outcome: SpanOutcome(
                        status: .completed,
                        attributes: ["tool.output": TraceRedactor.toolOutput(output.content)]
                    )
                )
                return result
            } catch is CancellationError {
                lastError = AgentError.cancelled
                break
            } catch {
                lastError = error
                if attempt < attempts {
                    await trace.record(
                        .retry(attempt: attempt + 1, maximumAttempts: attempts),
                        in: toolSpan
                    )
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
        let result = ToolResultItem(
            toolCallID: call.id,
            toolName: call.name,
            content: detail,
            isError: true
        )
        await trace.end(
            toolSpan,
            outcome: SpanOutcome(
                status: lastError as? AgentError == .cancelled ? .cancelled : .failed,
                error: lastError,
                attributes: ["tool.output": TraceRedactor.toolOutput(detail)]
            )
        )
        return result
    }

    private struct ModelStreamResult: Sendable {
        let response: ModelResponse
        let didStreamText: Bool
    }

    private func requestModel<Context: Sendable, Output: Sendable>(
        _ request: ModelRequest,
        configuration: RunConfiguration,
        trace: AgentRunTrace,
        span: SpanHandle?,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation,
        outputGuardrails: [AnyOutputGuardrail<Context, Output>] = [],
        guardrailContext: AgentGuardrailContext<Context>? = nil,
        emitTextDeltas: Bool = true
    ) async throws -> ModelStreamResult {
        var lastError: Error?
        for attempt in 1...configuration.retryPolicy.maximumAttempts {
            do {
                return try await withTimeout(configuration.modelTimeout, error: .modelTimedOut) {
                    var completed: ModelResponse?
                    let canStreamSafely = emitTextDeltas && (
                        outputGuardrails.isEmpty
                            || outputGuardrails.allSatisfy { $0.streamingBufferSize != nil }
                    )
                    let bufferSize = outputGuardrails.compactMap(\.streamingBufferSize).max() ?? 0
                    var pendingText = ""
                    var emittedContext = ""
                    var streamedText = ""
                    for try await event in self.provider.streamResponse(request: request) {
                        try Task.checkCancellation()
                        switch event {
                        case .textDelta(let delta):
                            guard canStreamSafely else { continue }
                            streamedText += delta
                            guard !outputGuardrails.isEmpty else {
                                events.yield(.textDelta(delta))
                                continue
                            }
                            pendingText += delta
                            guard let guardrailContext else {
                                throw AgentError.invalidConfiguration(
                                    "增量输出 Guardrail 缺少运行上下文"
                                )
                            }
                            let candidate = emittedContext + pendingText
                            for guardrail in outputGuardrails {
                                let result: GuardrailResult
                                do {
                                    let rawResult = try await guardrail.evaluateStreamingText(
                                        context: guardrailContext,
                                        text: candidate
                                    ) ?? GuardrailResult(
                                        action: .stop,
                                        message: "输出 Guardrail 不支持增量校验"
                                    )
                                    result = self.decorate(
                                        rawResult,
                                        name: guardrail.name,
                                        stage: .output
                                    )
                                } catch {
                                    result = self.guardrailFailure(
                                        name: guardrail.name,
                                        stage: .output,
                                        error: error
                                    )
                                }
                                guard result.action == .allow else {
                                    events.yield(.guardrailEvaluated(result))
                                    throw AgentError.guardrailTriggered(result)
                                }
                            }
                            if pendingText.count > bufferSize {
                                let end = pendingText.index(
                                    pendingText.endIndex,
                                    offsetBy: -bufferSize
                                )
                                let safeText = String(pendingText[..<end])
                                pendingText = String(pendingText[end...])
                                events.yield(.textDelta(safeText))
                                emittedContext = String(
                                    (emittedContext + safeText).suffix(bufferSize)
                                )
                            }
                        case .completed(let response): completed = response
                        }
                    }
                    guard let completed else {
                        throw AgentError.modelRequestFailed(.invalidResponse("模型流未返回完成事件"))
                    }
                    if canStreamSafely, !outputGuardrails.isEmpty, !pendingText.isEmpty {
                        events.yield(.textDelta(pendingText))
                    }
                    return ModelStreamResult(
                        response: completed,
                        didStreamText: canStreamSafely && streamedText == completed.content
                    )
                }
            } catch is CancellationError {
                throw AgentError.cancelled
            } catch AgentError.guardrailTriggered(let result) {
                throw AgentError.guardrailTriggered(result)
            } catch AgentError.invalidConfiguration(let detail) {
                throw AgentError.invalidConfiguration(detail)
            } catch {
                lastError = error
                if attempt < configuration.retryPolicy.maximumAttempts {
                    await trace.record(
                        .retry(
                            attempt: attempt + 1,
                            maximumAttempts: configuration.retryPolicy.maximumAttempts
                        ),
                        in: span
                    )
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
        guard (agent.tools.isEmpty && agent.handoffs.isEmpty)
                || provider.capabilities.supportsTools else {
            throw AgentError.modelRequestFailed(.unsupportedCapability("当前 Provider 不支持工具调用"))
        }
        guard agent.outputSchema == nil || provider.capabilities.supportsStructuredOutput else {
            throw AgentError.modelRequestFailed(
                .unsupportedCapability("当前 Provider 不支持 JSON Schema 结构化输出")
            )
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

    private func performHandoffIfRequested<Context: Sendable, Output: Sendable>(
        _ calls: [ToolCallItem],
        from source: AgentDefinition<Context, Output>,
        context: Context,
        trace: AgentRunTrace,
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws -> AgentDefinition<Context, Output>? {
        let matches = calls.compactMap { call -> (ToolCallItem, AgentHandoff<Context, Output>)? in
            guard let handoff = source.handoffs.first(where: { $0.toolName == call.name }) else {
                return nil
            }
            return (call, handoff)
        }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, calls.count == 1 else {
            throw AgentError.invalidConfiguration(
                "Handoff 必须是该模型轮次中唯一的工具调用"
            )
        }
        let (call, handoff) = matches[0]
        guard let data = call.arguments.data(using: .utf8) else {
            throw AgentError.invalidToolArguments(toolName: call.name, detail: "参数不是 UTF-8 文本")
        }
        let arguments: HandoffArguments
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reason = object["reason"] as? String,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentError.invalidToolArguments(
                    toolName: call.name,
                    detail: "reason 必须是非空字符串"
                )
            }
            arguments = HandoffArguments(
                reason: reason,
                metadata: try object["metadata"].map(JSONValue.init(any:))
            )
        } catch {
            if let error = error as? AgentError { throw error }
            throw AgentError.invalidToolArguments(
                toolName: call.name,
                detail: error.localizedDescription
            )
        }
        let metadata = arguments.metadata ?? handoff.metadata
        let span = await trace.startChild(
            kind: .handoff,
            name: "\(source.id) -> \(handoff.targetAgentID)",
            agentID: source.id,
            attributes: [
                "handoff.source": source.id,
                "handoff.target": handoff.targetAgentID,
                "handoff.reason": arguments.reason,
                "handoff.metadata": metadata == nil ? "absent" : "present"
            ]
        )
        let target = handoff.resolve()
        allItems = handoff.filterHistory(allItems)
        if !allItems.contains(where: {
            guard case .toolCall(let existing) = $0 else { return false }
            return existing.id == call.id
        }) {
            allItems.append(.toolCall(call))
        }
        let result = ToolResultItem(
            toolCallID: call.id,
            toolName: call.name,
            content: "Handoff accepted by \(target.name)",
            isError: false
        )
        appendToolResult(result, allItems: &allItems, newItems: &newItems, events: events)
        let item = AgentItem.handoff(HandoffItem(
            sourceAgentID: source.id,
            targetAgentID: target.id,
            reason: arguments.reason,
            metadata: metadata
        ))
        allItems.append(item)
        newItems.append(item)
        let instructions = try await target.instructions.resolve(using: context)
        let instructionItem = AgentItem.message(AgentMessageItem(
            role: .system,
            content: instructions
        ))
        allItems.append(instructionItem)
        newItems.append(instructionItem)
        events.yield(.handoff(HandoffEvent(
            sourceAgentID: source.id,
            targetAgentID: target.id,
            reason: arguments.reason,
            metadata: metadata
        )))
        await trace.end(span, outcome: SpanOutcome(status: .completed))
        await trace.switchAgent(to: target.id, name: target.name)
        return target
    }

    private func lastResponsibleAgentID(in items: [AgentItem]) -> String? {
        items.reversed().compactMap { item -> String? in
            guard case .handoff(let handoff) = item else { return nil }
            return handoff.targetAgentID
        }.first
    }

    private func traceCompaction(_ compaction: CompactionItem, trace: AgentRunTrace) async {
        let span = await trace.startChild(
            kind: .compaction,
            name: "context.compaction",
            attributes: [
                "compaction.summarized_items": String(compaction.summarizedItemCount),
                "compaction.summary_length": String(compaction.summary.utf8.count)
            ]
        )
        await trace.end(span, outcome: SpanOutcome(status: .completed))
    }

    private func traceApprovalRequest(
        _ interruption: AgentInterruption,
        trace: AgentRunTrace
    ) async {
        let span = await trace.startChild(
            kind: .approval,
            name: "tool.approval",
            attributes: [
                "approval.phase": "request",
                "tool.name": interruption.toolCall.name,
                "tool.call_id": interruption.toolCall.id,
                "summary": interruption.summary,
                "risk": interruption.riskLevel.rawValue
            ]
        )
        await trace.end(span, outcome: SpanOutcome(status: .interrupted))
    }

    private func traceApprovalDecision(
        _ interruption: AgentInterruption,
        decision: ApprovalDecision,
        trace: AgentRunTrace
    ) async {
        let value: String
        switch decision {
        case .approved: value = "approved"
        case .rejected: value = "rejected"
        }
        let span = await trace.startChild(
            kind: .approval,
            name: "tool.approval",
            attributes: [
                "approval.phase": "decision",
                "tool.name": interruption.toolCall.name,
                "tool.call_id": interruption.toolCall.id,
                "summary": interruption.summary
            ]
        )
        await trace.record(.approval(decision: value), in: span)
        await trace.end(span, outcome: SpanOutcome(
            status: .completed,
            attributes: ["approval.decision": value]
        ))
    }

    private func endGuardrailSpan(
        _ span: SpanHandle?,
        result: GuardrailResult,
        trace: AgentRunTrace
    ) async {
        let status: AgentSpanStatus
        switch result.action {
        case .allow: status = .completed
        case .requireApproval: status = .interrupted
        case .stop: status = .failed
        }
        await trace.end(span, outcome: SpanOutcome(
            status: status,
            attributes: [
                "guardrail.action": result.action.rawValue,
                "guardrail.message": result.message
            ]
        ))
    }

    private func evaluateInputGuardrail<Context: Sendable>(
        _ guardrail: AnyInputGuardrail<Context>,
        context: AgentGuardrailContext<Context>,
        input: AgentInput,
        trace: AgentRunTrace
    ) async -> GuardrailResult {
        let span = await trace.startChild(
            kind: .guardrail,
            name: guardrail.name,
            agentID: context.agentID,
            attributes: ["guardrail.stage": GuardrailStage.input.rawValue]
        )
        let result: GuardrailResult
        do {
            result = decorate(
                try await guardrail.evaluate(context: context, input: input),
                name: guardrail.name,
                stage: .input
            )
        } catch {
            result = guardrailFailure(name: guardrail.name, stage: .input, error: error)
        }
        await endGuardrailSpan(span, result: result, trace: trace)
        return result
    }

    private func evaluateOutputGuardrail<Context: Sendable, Output: Sendable>(
        _ guardrail: AnyOutputGuardrail<Context, Output>,
        context: AgentGuardrailContext<Context>,
        output: Output,
        trace: AgentRunTrace
    ) async -> GuardrailResult {
        let span = await trace.startChild(
            kind: .guardrail,
            name: guardrail.name,
            agentID: context.agentID,
            attributes: ["guardrail.stage": GuardrailStage.output.rawValue]
        )
        let result: GuardrailResult
        do {
            result = decorate(
                try await guardrail.evaluate(context: context, output: output),
                name: guardrail.name,
                stage: .output
            )
        } catch {
            result = guardrailFailure(name: guardrail.name, stage: .output, error: error)
        }
        await endGuardrailSpan(span, result: result, trace: trace)
        return result
    }

    private func evaluateToolInputGuardrail<Context: Sendable>(
        _ guardrail: AnyToolGuardrail<Context>,
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        tool: ToolDefinition,
        trace: AgentRunTrace
    ) async -> GuardrailResult {
        let span = await trace.startChild(
            kind: .guardrail,
            name: guardrail.name,
            agentID: context.agentID,
            attributes: [
                "guardrail.stage": GuardrailStage.toolInput.rawValue,
                "tool.name": call.name,
                "tool.call_id": call.id
            ]
        )
        let result: GuardrailResult
        do {
            result = decorate(
                try await guardrail.evaluateInput(context: context, call: call, tool: tool),
                name: guardrail.name,
                stage: .toolInput,
                toolCallID: call.id
            )
        } catch {
            result = guardrailFailure(
                name: guardrail.name,
                stage: .toolInput,
                toolCallID: call.id,
                error: error
            )
        }
        await endGuardrailSpan(span, result: result, trace: trace)
        return result
    }

    private func applyToolOutputGuardrails<Context: Sendable>(
        _ guardrails: [AnyToolGuardrail<Context>],
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem,
        guardrailResults: inout [GuardrailResult],
        allItems: inout [AgentItem],
        newItems: inout [AgentItem],
        trace: AgentRunTrace,
        events: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
    ) async throws {
        for guardrail in guardrails {
            let span = await trace.startChild(
                kind: .guardrail,
                name: guardrail.name,
                agentID: context.agentID,
                attributes: [
                    "guardrail.stage": GuardrailStage.toolOutput.rawValue,
                    "tool.name": call.name,
                    "tool.call_id": call.id
                ]
            )
            let evaluated: GuardrailResult
            do {
                evaluated = decorate(
                    try await guardrail.evaluateOutput(
                        context: context,
                        call: call,
                        result: result
                    ),
                    name: guardrail.name,
                    stage: .toolOutput,
                    toolCallID: call.id
                )
            } catch {
                evaluated = guardrailFailure(
                    name: guardrail.name,
                    stage: .toolOutput,
                    toolCallID: call.id,
                    error: error
                )
            }
            await endGuardrailSpan(span, result: evaluated, trace: trace)
            guardrailResults.append(evaluated)
            events.yield(.guardrailEvaluated(evaluated))
            let item = AgentItem.guardrail(GuardrailItem(result: evaluated))
            allItems.append(item)
            newItems.append(item)
            guard evaluated.action == .allow else {
                throw AgentError.guardrailTriggered(evaluated)
            }
        }
    }

    private func decorate(
        _ result: GuardrailResult,
        name: String,
        stage: GuardrailStage,
        toolCallID: String? = nil
    ) -> GuardrailResult {
        GuardrailResult(
            action: result.action,
            message: result.message,
            guardrailName: result.guardrailName ?? name,
            stage: result.stage ?? stage,
            toolCallID: result.toolCallID ?? toolCallID
        )
    }

    private func guardrailFailure(
        name: String,
        stage: GuardrailStage,
        toolCallID: String? = nil,
        error: Error
    ) -> GuardrailResult {
        GuardrailResult(
            action: .stop,
            message: "Guardrail \(name) 执行失败：\(error.localizedDescription)",
            guardrailName: name,
            stage: stage,
            toolCallID: toolCallID
        )
    }

    private func interruptedResult<Output: Sendable>(
        runID: UUID,
        agentID: String,
        allItems: [AgentItem],
        newItems: [AgentItem],
        usage: AgentUsage,
        rawResponses: [ModelResponse],
        guardrailResults: [GuardrailResult],
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
            guardrailResults: guardrailResults,
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
