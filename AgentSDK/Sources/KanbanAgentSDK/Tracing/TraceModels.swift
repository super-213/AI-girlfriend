import Foundation

public enum AgentSpanKind: String, Codable, Sendable {
    case run
    case agent
    case model
    case tool
    case guardrail
    case approval
    case handoff
    case compaction
}

public enum AgentSpanStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case interrupted
    case cancelled
}

public struct AgentTraceContext: Codable, Equatable, Sendable {
    public let traceID: UUID
    public let parentSpanID: UUID
}

public struct SpanDefinition: Codable, Equatable, Sendable {
    public let traceID: UUID
    public let spanID: UUID
    public let parentSpanID: UUID?
    public let runID: UUID
    public let sessionID: String
    public let agentID: String
    public let kind: AgentSpanKind
    public let name: String
    public let startedAt: Date
    public let providerID: String?
    public let modelID: String?
    public let attributes: [String: String]

    public init(
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

public struct SpanHandle: Codable, Equatable, Hashable, Sendable {
    public let traceID: UUID
    public let spanID: UUID
}

public struct TraceError: Codable, Equatable, Sendable {
    public let type: String
    public let message: String

    public init(_ error: Error) {
        type = String(describing: Swift.type(of: error))
        message = TraceRedactor.summary(error.localizedDescription)
    }
}

public enum TraceEvent: Codable, Equatable, Sendable {
    case attributes([String: String])
    case usage(AgentUsage)
    case retry(attempt: Int, maximumAttempts: Int)
    case approval(decision: String)
    case error(TraceError)
}

public struct SpanOutcome: Codable, Equatable, Sendable {
    public let status: AgentSpanStatus
    public let endedAt: Date
    public let usage: AgentUsage?
    public let error: TraceError?
    public let attributes: [String: String]

    public init(
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

public struct TraceSpanRecord: Codable, Equatable, Sendable {
    public let definition: SpanDefinition
    public var events: [TraceEvent]
    public var outcome: SpanOutcome?

    public var duration: TimeInterval? {
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
