import Foundation

protocol OutputGuardrail: Sendable {
    associatedtype Context: Sendable
    associatedtype Output: Sendable
    var name: String { get }
    func evaluate(
        context: AgentGuardrailContext<Context>,
        output: Output
    ) async throws -> GuardrailResult
}

struct AnyOutputGuardrail<Context: Sendable, Output: Sendable>: Sendable {
    let name: String
    private let evaluateValue: @Sendable (
        AgentGuardrailContext<Context>, Output
    ) async throws -> GuardrailResult

    init<G: OutputGuardrail>(_ guardrail: G)
    where G.Context == Context, G.Output == Output {
        name = guardrail.name
        evaluateValue = guardrail.evaluate
    }

    func evaluate(
        context: AgentGuardrailContext<Context>,
        output: Output
    ) async throws -> GuardrailResult {
        try await evaluateValue(context, output)
    }
}
