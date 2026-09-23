import Foundation

public struct AgentUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public static let zero = AgentUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)

    public mutating func add(_ other: AgentUsage?) {
        guard let other else { return }
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
    }
}

public struct RunResult<Output: Sendable>: Sendable {
    public let runID: UUID
    public let finalOutput: Output?
    public let history: [AgentItem]
    public let newItems: [AgentItem]
    public let lastAgentID: String
    public let usage: AgentUsage
    public let rawResponses: [ModelResponse]
    public let guardrailResults: [GuardrailResult]
    public let interruptions: [AgentInterruption]
    public let resumableState: RunState?
}

public struct AgentRun<Output: Sendable>: Sendable {
    public let events: AsyncThrowingStream<AgentRunEvent, Error>
    public let result: Task<RunResult<Output>, Error>

    public func cancel() {
        result.cancel()
    }
}
