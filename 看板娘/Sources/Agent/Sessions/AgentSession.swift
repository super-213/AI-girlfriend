import Foundation

protocol AgentSession: Sendable {
    var id: String { get }

    func loadItems() async throws -> [AgentItem]
    func append(_ items: [AgentItem]) async throws
    func replaceItems(_ items: [AgentItem]) async throws
    func loadRunState() async throws -> RunState?
    func saveRunState(_ state: RunState?) async throws
}
