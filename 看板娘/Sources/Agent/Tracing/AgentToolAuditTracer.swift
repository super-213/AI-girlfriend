import Foundation

actor AgentToolAuditTracer: AgentTracer {
    private var definitions: [UUID: SpanDefinition] = [:]
    private var events: [UUID: [TraceEvent]] = [:]

    func startSpan(_ definition: SpanDefinition) async -> SpanHandle {
        definitions[definition.spanID] = definition
        guard definition.kind == .tool || definition.kind == .approval else {
            return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
        }
        if definition.kind == .approval,
           definition.attributes["approval.phase"] == "decision" {
            return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
        }
        let status: AgentToolAuditEntry.Status = definition.kind == .approval ? .requested : .running
        await MainActor.run {
            AgentToolAuditStore.shared.record(
                toolName: definition.attributes["tool.name"] ?? definition.name,
                summary: definition.attributes["summary"] ?? definition.name,
                status: status
            )
        }
        return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
    }

    func record(_ event: TraceEvent, in span: SpanHandle) async {
        events[span.spanID, default: []].append(event)
    }

    func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async {
        guard let definition = definitions.removeValue(forKey: span.spanID),
              definition.kind == .tool || definition.kind == .approval else { return }
        let recordedEvents = events.removeValue(forKey: span.spanID) ?? []
        if definition.kind == .approval, outcome.status == .interrupted { return }
        let decision = recordedEvents.compactMap { event -> String? in
            guard case .approval(let value) = event else { return nil }
            return value
        }.last
        let status: AgentToolAuditEntry.Status
        if definition.kind == .approval {
            status = decision == "approved" ? .approved : .declined
        } else {
            status = outcome.status == .completed ? .succeeded : .failed
        }
        await MainActor.run {
            AgentToolAuditStore.shared.record(
                toolName: definition.attributes["tool.name"] ?? definition.name,
                summary: definition.attributes["summary"] ?? definition.name,
                status: status,
                detail: outcome.attributes["tool.output"] ?? outcome.error?.message
            )
        }
    }
}

enum AppAgentTracer {
    static let shared: any AgentTracer = CompositeAgentTracer(tracers: [
        LocalAgentTracer.shared,
        AgentToolAuditTracer()
    ])
}
