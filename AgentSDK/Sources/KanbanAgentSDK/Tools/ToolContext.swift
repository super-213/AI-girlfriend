import Foundation

public struct ToolContext<Context: Sendable>: Sendable {
    public let runID: UUID
    public let sessionID: String
    public let agentID: String
    public let context: Context
    public let traceContext: AgentTraceContext?

    public init(
        runID: UUID,
        sessionID: String,
        agentID: String,
        context: Context,
        traceContext: AgentTraceContext? = nil
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.context = context
        self.traceContext = traceContext
    }
}

public struct ToolInvocationOutput: Sendable, Equatable {
    public let content: String
    public let imagePaths: [String]

    public init(content: String, imagePaths: [String] = []) {
        self.content = content
        self.imagePaths = imagePaths
    }
}
