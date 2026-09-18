import Foundation

enum AgentSpanKind: String, Codable, Sendable {
    case run
    case agent
    case model
    case tool
    case guardrail
    case approval
    case handoff
    case compaction
}

enum AgentSpanStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case interrupted
    case cancelled
}

struct AgentTraceContext: Codable, Equatable, Sendable {
    let traceID: UUID
    let parentSpanID: UUID
}

struct SpanDefinition: Codable, Equatable, Sendable {
    let traceID: UUID
    let spanID: UUID
    let parentSpanID: UUID?
    let runID: UUID
    let sessionID: String
    let agentID: String
    let kind: AgentSpanKind
    let name: String
    let startedAt: Date
    let providerID: String?
    let modelID: String?
    let attributes: [String: String]

    init(
        traceID: UUID,
        spanID: UUID = UUID(),
        parentSpanID: UUID? = nil,
        runID: UUID,
        sessionID: String,
        agentID: String,
        kind: AgentSpanKind,
        name: String,
        startedAt: Date = .now,
        providerID: String? = nil,
        modelID: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.kind = kind
        self.name = name
        self.startedAt = startedAt
        self.providerID = providerID
        self.modelID = modelID
        self.attributes = TraceRedactor.redact(attributes)
    }
}

struct SpanHandle: Codable, Equatable, Hashable, Sendable {
    let traceID: UUID
    let spanID: UUID
}

struct TraceError: Codable, Equatable, Sendable {
    let type: String
    let message: String

    init(_ error: Error) {
        type = String(describing: Swift.type(of: error))
        message = TraceRedactor.summary(error.localizedDescription)
    }
}

enum TraceEvent: Codable, Equatable, Sendable {
    case attributes([String: String])
    case usage(AgentUsage)
    case retry(attempt: Int, maximumAttempts: Int)
    case approval(decision: String)
    case error(TraceError)
}

struct SpanOutcome: Codable, Equatable, Sendable {
    let status: AgentSpanStatus
    let endedAt: Date
    let usage: AgentUsage?
    let error: TraceError?
    let attributes: [String: String]

    init(
        status: AgentSpanStatus,
        endedAt: Date = .now,
        usage: AgentUsage? = nil,
        error: Error? = nil,
        attributes: [String: String] = [:]
    ) {
        self.status = status
        self.endedAt = endedAt
        self.usage = usage
        self.error = error.map(TraceError.init)
        self.attributes = TraceRedactor.redact(attributes)
    }
}

struct TraceSpanRecord: Codable, Equatable, Sendable {
    let definition: SpanDefinition
    var events: [TraceEvent]
    var outcome: SpanOutcome?

    var duration: TimeInterval? {
        outcome.map { $0.endedAt.timeIntervalSince(definition.startedAt) }
    }
}

enum TraceRedactor {
    static let maximumSummaryLength = 512

    static func summary(_ value: String) -> String {
        let redacted = SensitiveDataRedactor.redact(value)
        guard redacted.count > maximumSummaryLength else { return redacted }
        return String(redacted.prefix(maximumSummaryLength))
            + "… <truncated \(redacted.count - maximumSummaryLength) chars>"
    }

    static func redact(_ attributes: [String: String]) -> [String: String] {
        attributes.mapValues(summary)
    }

    static func event(_ event: TraceEvent) -> TraceEvent {
        switch event {
        case .attributes(let attributes):
            return .attributes(redact(attributes))
        case .usage, .retry, .approval, .error:
            return event
        }
    }

    static func toolArguments(_ value: String) -> String {
        "length=\(value.utf8.count); \(shape(of: value))"
    }

    static func toolOutput(_ value: String) -> String {
        "length=\(value.utf8.count); lines=\(value.split(separator: "\n", omittingEmptySubsequences: false).count); \(shape(of: value))"
    }

    private static func shape(of value: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return "type=text"
        }
        switch object {
        case let dictionary as [String: Any]:
            return "type=object; keys=\(dictionary.keys.sorted().joined(separator: ","))"
        case let array as [Any]:
            return "type=array; count=\(array.count)"
        case is String: return "type=string"
        case is NSNumber: return "type=number_or_bool"
        case is NSNull: return "type=null"
        default: return "type=json"
        }
    }
}
