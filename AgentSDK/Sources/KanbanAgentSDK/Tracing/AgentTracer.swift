import Foundation

public protocol AgentTracer: Sendable {
    func startSpan(_ definition: SpanDefinition) async -> SpanHandle
    func record(_ event: TraceEvent, in span: SpanHandle) async
    func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async
}

public actor InMemoryAgentTracer: AgentTracer {
    private var orderedSpanIDs: [UUID] = []
    private var recordsByID: [UUID: TraceSpanRecord] = [:]

    public func startSpan(_ definition: SpanDefinition) async -> SpanHandle {
        orderedSpanIDs.append(definition.spanID)
        recordsByID[definition.spanID] = TraceSpanRecord(
            definition: definition,
            events: [],
            outcome: nil
        )
        return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
    }

    public func record(_ event: TraceEvent, in span: SpanHandle) async {
        recordsByID[span.spanID]?.events.append(TraceRedactor.event(event))
    }

    public func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async {
        recordsByID[span.spanID]?.outcome = outcome
    }

    public func records() -> [TraceSpanRecord] {
        orderedSpanIDs.compactMap { recordsByID[$0] }
    }

    public func reset() {
        orderedSpanIDs.removeAll()
        recordsByID.removeAll()
    }

}

public actor LocalAgentTracer: AgentTracer {
    public static let shared = LocalAgentTracer()

    private let persistenceURL: URL?
    private let limit: Int
    private var orderedSpanIDs: [UUID] = []
    private var recordsByID: [UUID: TraceSpanRecord] = [:]

    public init(persistenceURL: URL? = nil, limit: Int = 500) {
        self.persistenceURL = persistenceURL
        self.limit = max(1, limit)
    }

    public func startSpan(_ definition: SpanDefinition) async -> SpanHandle {
        orderedSpanIDs.append(definition.spanID)
        recordsByID[definition.spanID] = TraceSpanRecord(
            definition: definition,
            events: [],
            outcome: nil
        )
        trimIfNeeded()
        return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
    }

    public func record(_ event: TraceEvent, in span: SpanHandle) async {
        recordsByID[span.spanID]?.events.append(TraceRedactor.event(event))
    }

    public func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async {
        recordsByID[span.spanID]?.outcome = outcome
        persistBestEffort()
    }

    public func records(traceID: UUID? = nil) -> [TraceSpanRecord] {
        orderedSpanIDs.compactMap { recordsByID[$0] }.filter {
            traceID == nil || $0.definition.traceID == traceID
        }
    }

    private func trimIfNeeded() {
        while orderedSpanIDs.count > limit {
            recordsByID.removeValue(forKey: orderedSpanIDs.removeFirst())
        }
    }

    private func persistBestEffort() {
        guard let persistenceURL else { return }
        do {
            let records = orderedSpanIDs.compactMap { recordsByID[$0] }
            let data = try JSONEncoder().encode(records)
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Tracing is observability-only and must never change run behavior.
        }
    }
}

public struct CompositeAgentTracer: AgentTracer {
    public let tracers: [any AgentTracer]

    public func startSpan(_ definition: SpanDefinition) async -> SpanHandle {
        for tracer in tracers { _ = await tracer.startSpan(definition) }
        return SpanHandle(traceID: definition.traceID, spanID: definition.spanID)
    }

    public func record(_ event: TraceEvent, in span: SpanHandle) async {
        for tracer in tracers { await tracer.record(event, in: span) }
    }

    public func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async {
        for tracer in tracers { await tracer.endSpan(span, outcome: outcome) }
    }
}
