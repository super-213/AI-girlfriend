import Foundation

public protocol AgentTool: Sendable {
    associatedtype Context: Sendable
    associatedtype Arguments: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var definition: ToolDefinition { get }
    static var behavior: ToolBehavior { get }

    func invoke(context: ToolContext<Context>, arguments: Arguments) async throws -> Output
}

public extension AgentTool {
    static var behavior: ToolBehavior { .readOnly }
}
