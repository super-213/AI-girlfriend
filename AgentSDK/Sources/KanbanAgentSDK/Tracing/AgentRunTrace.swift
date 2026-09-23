import Foundation

actor AgentRunTrace {
    private let tracer: any AgentTracer
    private let enabled: Bool
    let traceID: UUID
    let runID: UUID
    let sessionID: String

    private var runSpan: SpanHandle?
    private var agentSpan: SpanHandle?
    private var currentAgentID: String

    init(
        tracer: any AgentTracer,
        enabled: Bool,
        traceID: UUID,
        runID: UUID,
        sessionID: String,
        agentID: String
    ) {
        self.tracer = tracer
        self.enabled = enabled
        self.traceID = traceID
        self.runID = runID
        self.sessionID = sessionID
        currentAgentID = agentID
    }

    func start(agentID: String, agentName: String, parentSpanID: UUID? = nil) async {
        guard enabled else { return }
        currentAgentID = agentID
        runSpan = await startSpan(
            kind: .run,
            name: "agent.run",
            agentID: agentID,
            parentSpanID: parentSpanID
        )
        agentSpan = await startSpan(
            kind: .agent,
            name: agentName,
            agentID: agentID,
            parentSpanID: runSpan?.spanID
        )
    }

    func startChild(
        kind: AgentSpanKind,
        name: String,
        agentID: String? = nil,
        parentSpanID: UUID? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        attributes: [String: String] = [:]
    ) async -> SpanHandle? {
        guard enabled else { return nil }
        return await startSpan(
            kind: kind,
            name: name,
            agentID: agentID ?? currentAgentID,
            parentSpanID: parentSpanID ?? agentSpan?.spanID,
            providerID: providerID,
            modelID: modelID,
            attributes: attributes
        )
    }

    func record(_ event: TraceEvent, in span: SpanHandle?) async {
        guard enabled, let span else { return }
        await tracer.record(event, in: span)
    }

    func end(_ span: SpanHandle?, outcome: SpanOutcome) async {
        guard enabled, let span else { return }
        await tracer.endSpan(span, outcome: outcome)
    }

    func switchAgent(to agentID: String, name: String) async {
        guard enabled else {
            currentAgentID = agentID
            return
        }
        if let agentSpan {
            await tracer.endSpan(agentSpan, outcome: SpanOutcome(status: .completed))
        }
        currentAgentID = agentID
        agentSpan = await startSpan(
            kind: .agent,
            name: name,
            agentID: agentID,
            parentSpanID: runSpan?.spanID
        )
    }

    func finish(status: AgentSpanStatus, usage: AgentUsage? = nil, error: Error? = nil) async {
        guard enabled else { return }
        let outcome = SpanOutcome(status: status, usage: usage, error: error)
        if let agentSpan { await tracer.endSpan(agentSpan, outcome: outcome) }
        if let runSpan { await tracer.endSpan(runSpan, outcome: outcome) }
        agentSpan = nil
        runSpan = nil
    }

    func currentParentContext() -> AgentTraceContext? {
        guard enabled, let agentSpan else { return nil }
        return AgentTraceContext(traceID: traceID, parentSpanID: agentSpan.spanID)
    }

    private func startSpan(
        kind: AgentSpanKind,
        name: String,
        agentID: String,
        parentSpanID: UUID?,
        providerID: String? = nil,
        modelID: String? = nil,
        attributes: [String: String] = [:]
    ) async -> SpanHandle {
        await tracer.startSpan(SpanDefinition(
            traceID: traceID,
            parentSpanID: parentSpanID,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            kind: kind,
            name: name,
            providerID: providerID,
            modelID: modelID,
            attributes: attributes
        ))
    }
}
