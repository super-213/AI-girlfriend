import Foundation

public struct AgentGuardrailContext<Context: Sendable>: Sendable {
    public let runID: UUID
    public let sessionID: String
    public let agentID: String
    public let context: Context
}

public protocol InputGuardrail: Sendable {
    associatedtype Context: Sendable
    var name: String { get }
    func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult
}

public struct AnyInputGuardrail<Context: Sendable>: Sendable {
    public let name: String
    private let evaluateValue: @Sendable (
        AgentGuardrailContext<Context>, AgentInput
    ) async throws -> GuardrailResult

    init<G: InputGuardrail>(_ guardrail: G) where G.Context == Context {
        name = guardrail.name
        evaluateValue = guardrail.evaluate
    }

    public func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult {
        try await evaluateValue(context, input)
    }
}

public struct NonEmptyInputGuardrail<Context: Sendable>: InputGuardrail {
    public let name = "non_empty_input"

    public func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult {
        input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? GuardrailResult(action: .stop, message: "输入不能为空")
            : .allowed
    }
}
