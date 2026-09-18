import Foundation

struct ToolContext<Context: Sendable>: Sendable {
    let runID: UUID
    let sessionID: String
    let agentID: String
    let context: Context
    let traceContext: AgentTraceContext?

    init(
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

struct ToolInvocationOutput: Sendable, Equatable {
    let content: String
    let imagePaths: [String]

    init(content: String, imagePaths: [String] = []) {
        self.content = content
        self.imagePaths = imagePaths
    }
}
