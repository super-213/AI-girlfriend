import Foundation

struct AgentFileAccessPolicy: Codable, Equatable, Sendable {
    var readableRoots: [String]
    var writableRoots: [String]

    static let inherited = AgentFileAccessPolicy(readableRoots: [], writableRoots: [])
}

struct AppAgentContext: Sendable {
    let conversationID: UUID
    let projectID: UUID?
    let workspacePath: String?
    let characterID: String?
    let fileAccessPolicy: AgentFileAccessPolicy
    let commandPermissionPolicy: CommandPermissionPolicy
}
