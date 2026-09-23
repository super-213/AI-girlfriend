import Foundation

public protocol OutputGuardrail: Sendable {
    associatedtype Context: Sendable
    associatedtype Output: Sendable
    var name: String { get }
    func evaluate(
        context: AgentGuardrailContext<Context>,
        output: Output
    ) async throws -> GuardrailResult
}

/// An output guardrail that can safely validate text while it is still streaming.
///
/// The runner retains `streamingBufferSize` trailing characters before publishing them,
/// so a sensitive token split across adjacent provider chunks is evaluated as one value.
/// Guardrails that need the complete model response must keep using `OutputGuardrail` only.
public protocol StreamingTextOutputGuardrail: OutputGuardrail where Output == String {
    var streamingBufferSize: Int { get }

    func evaluateStreamingText(
        context: AgentGuardrailContext<Context>,
        text: String
    ) async throws -> GuardrailResult
}

public extension StreamingTextOutputGuardrail {
    var streamingBufferSize: Int { 64 }

    func evaluateStreamingText(
        context: AgentGuardrailContext<Context>,
        text: String
    ) async throws -> GuardrailResult {
        try await evaluate(context: context, output: text)
    }
}

public struct AnyOutputGuardrail<Context: Sendable, Output: Sendable>: Sendable {
    public let name: String
    public let streamingBufferSize: Int?
    private let evaluateValue: @Sendable (
        AgentGuardrailContext<Context>, Output
    ) async throws -> GuardrailResult
    private let evaluateStreamingTextValue: (@Sendable (
        AgentGuardrailContext<Context>, String
    ) async throws -> GuardrailResult)?

    init<G: OutputGuardrail>(_ guardrail: G)
    where G.Context == Context, G.Output == Output {
        name = guardrail.name
        streamingBufferSize = nil
        evaluateValue = guardrail.evaluate
        evaluateStreamingTextValue = nil
    }

    init<G: StreamingTextOutputGuardrail>(streaming guardrail: G)
    where G.Context == Context, Output == String {
        name = guardrail.name
        streamingBufferSize = max(0, guardrail.streamingBufferSize)
        evaluateValue = guardrail.evaluate
        evaluateStreamingTextValue = guardrail.evaluateStreamingText
    }

    public func evaluate(
        context: AgentGuardrailContext<Context>,
        output: Output
    ) async throws -> GuardrailResult {
        try await evaluateValue(context, output)
    }

    public func evaluateStreamingText(
        context: AgentGuardrailContext<Context>,
        text: String
    ) async throws -> GuardrailResult? {
        try await evaluateStreamingTextValue?(context, text)
    }
}
