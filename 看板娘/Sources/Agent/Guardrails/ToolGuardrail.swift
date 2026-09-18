import Foundation

protocol ToolGuardrail: Sendable {
    associatedtype Context: Sendable
    var name: String { get }
    func evaluateInput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        tool: ToolDefinition
    ) async throws -> GuardrailResult
    func evaluateOutput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult
}

extension ToolGuardrail {
    func evaluateOutput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult { .allowed }
}

struct AnyToolGuardrail<Context: Sendable>: Sendable {
    let name: String
    private let evaluateInputValue: @Sendable (
        AgentGuardrailContext<Context>, ToolCallItem, ToolDefinition
    ) async throws -> GuardrailResult
    private let evaluateOutputValue: @Sendable (
        AgentGuardrailContext<Context>, ToolCallItem, ToolResultItem
    ) async throws -> GuardrailResult

    init<G: ToolGuardrail>(_ guardrail: G) where G.Context == Context {
        name = guardrail.name
        evaluateInputValue = guardrail.evaluateInput
        evaluateOutputValue = guardrail.evaluateOutput
    }

    func evaluateInput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        tool: ToolDefinition
    ) async throws -> GuardrailResult {
        try await evaluateInputValue(context, call, tool)
    }

    func evaluateOutput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult {
        try await evaluateOutputValue(context, call, result)
    }
}
