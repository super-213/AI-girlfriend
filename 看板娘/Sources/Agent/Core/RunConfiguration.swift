import Foundation

struct RetryPolicy: Sendable {
    var maximumAttempts: Int
    var initialDelay: Duration

    static let standard = RetryPolicy(maximumAttempts: 2, initialDelay: .milliseconds(300))
    static let none = RetryPolicy(maximumAttempts: 1, initialDelay: .zero)
}

struct RunConfiguration: Sendable {
    var maxTurns: Int
    var modelTimeout: Duration
    var toolTimeout: Duration
    var maximumConcurrentTools: Int
    var retryPolicy: RetryPolicy
    var tracingEnabled: Bool
    var contextCompactionPolicy: AgentContextCompactionPolicy?
    var forceContextCompaction: Bool

    init(
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

    func validate() throws {
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
