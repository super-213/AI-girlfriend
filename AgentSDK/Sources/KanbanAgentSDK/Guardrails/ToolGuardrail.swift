import Foundation

public protocol ToolGuardrail: Sendable {
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

public extension ToolGuardrail {
    func evaluateOutput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult { .allowed }
}

public struct AnyToolGuardrail<Context: Sendable>: Sendable {
    public let name: String
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

    public func evaluateInput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        tool: ToolDefinition
    ) async throws -> GuardrailResult {
        try await evaluateInputValue(context, call, tool)
    }

    public func evaluateOutput(
        context: AgentGuardrailContext<Context>,
        call: ToolCallItem,
        result: ToolResultItem
    ) async throws -> GuardrailResult {
        try await evaluateOutputValue(context, call, result)
    }
}
