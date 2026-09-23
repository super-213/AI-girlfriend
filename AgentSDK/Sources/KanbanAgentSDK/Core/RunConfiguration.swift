import Foundation

public struct RetryPolicy: Sendable {
    public var maximumAttempts: Int
    public var initialDelay: Duration

    public static let standard = RetryPolicy(maximumAttempts: 2, initialDelay: .milliseconds(300))
    public static let none = RetryPolicy(maximumAttempts: 1, initialDelay: .zero)
}

public struct RunConfiguration: Sendable {
    public var maxTurns: Int
    public var modelTimeout: Duration
    public var toolTimeout: Duration
    public var maximumConcurrentTools: Int
    public var retryPolicy: RetryPolicy
    public var tracingEnabled: Bool
    public var contextCompactionPolicy: AgentContextCompactionPolicy?
    public var forceContextCompaction: Bool

    public init(
        maxTurns: Int = 20,
        modelTimeout: Duration = .seconds(120),
        toolTimeout: Duration = .seconds(60),
        maximumConcurrentTools: Int = 1,
        retryPolicy: RetryPolicy = .standard,
        tracingEnabled: Bool = true,
        contextCompactionPolicy: AgentContextCompactionPolicy? = nil,
        forceContextCompaction: Bool = false
    ) {
        self.maxTurns = maxTurns
        self.modelTimeout = modelTimeout
        self.toolTimeout = toolTimeout
        self.maximumConcurrentTools = maximumConcurrentTools
        self.retryPolicy = retryPolicy
        self.tracingEnabled = tracingEnabled
        self.contextCompactionPolicy = contextCompactionPolicy
        self.forceContextCompaction = forceContextCompaction
    }

    public func validate() throws {
        guard maxTurns > 0 else {
            throw AgentError.invalidConfiguration("maxTurns 必须大于 0")
        }
        guard maximumConcurrentTools > 0 else {
            throw AgentError.invalidConfiguration("maximumConcurrentTools 必须大于 0")
        }
        guard retryPolicy.maximumAttempts > 0 else {
            throw AgentError.invalidConfiguration("retryPolicy.maximumAttempts 必须大于 0")
        }
    }
}
