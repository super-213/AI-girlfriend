import Foundation

struct AgentUsage: Codable, Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int

    static let zero = AgentUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)

    mutating func add(_ other: AgentUsage?) {
        guard let other else { return }
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
    }
}

struct RunResult<Output: Sendable>: Sendable {
    let runID: UUID
    let finalOutput: Output?
    let history: [AgentItem]
    let newItems: [AgentItem]
    let lastAgentID: String
    let usage: AgentUsage
    let rawResponses: [ModelResponse]
    let guardrailResults: [GuardrailResult]
    let interruptions: [AgentInterruption]
    let resumableState: RunState?
}

struct AgentRun<Output: Sendable>: Sendable {
    let events: AsyncThrowingStream<AgentRunEvent, Error>
    let result: Task<RunResult<Output>, Error>

    func cancel() {
        result.cancel()
    }
}
