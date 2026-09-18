import Foundation

struct ToolContext<Context: Sendable>: Sendable {
    let runID: UUID
    let sessionID: String
    let agentID: String
    let context: Context
}

struct ToolInvocationOutput: Sendable, Equatable {
    let content: String
    let imagePaths: [String]

    init(content: String, imagePaths: [String] = []) {
        self.content = content
        self.imagePaths = imagePaths
    }
}
