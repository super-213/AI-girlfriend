import Foundation

struct AgentGuardrailContext<Context: Sendable>: Sendable {
    let runID: UUID
    let sessionID: String
    let agentID: String
    let context: Context
}

protocol InputGuardrail: Sendable {
    associatedtype Context: Sendable
    var name: String { get }
    func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult
}

struct AnyInputGuardrail<Context: Sendable>: Sendable {
    let name: String
    private let evaluateValue: @Sendable (
        AgentGuardrailContext<Context>, AgentInput
    ) async throws -> GuardrailResult

    init<G: InputGuardrail>(_ guardrail: G) where G.Context == Context {
        name = guardrail.name
        evaluateValue = guardrail.evaluate
    }

    func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult {
        try await evaluateValue(context, input)
    }
}

struct NonEmptyInputGuardrail<Context: Sendable>: InputGuardrail {
    let name = "non_empty_input"

    func evaluate(
        context: AgentGuardrailContext<Context>,
        input: AgentInput
    ) async throws -> GuardrailResult {
        input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? GuardrailResult(action: .stop, message: "输入不能为空")
            : .allowed
    }
}
