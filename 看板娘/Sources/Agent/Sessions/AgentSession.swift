import Foundation

protocol AgentSession: Sendable {
    var id: String { get }

    func loadItems() async throws -> [AgentItem]
    func append(_ items: [AgentItem]) async throws
    func replaceItems(_ items: [AgentItem]) async throws
    func loadRunState() async throws -> RunState?
    func saveRunState(_ state: RunState?) async throws
}

extension AgentSession {
    func snapshot(
        createdAt: Date,
        agentID: String,
        providerConfigurationID: String
    ) async throws -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            sessionID: id,
            createdAt: createdAt,
            updatedAt: .now,
            agentID: agentID,
            providerConfigurationID: providerConfigurationID,
            items: try await loadItems(),
            pendingRunState: try await loadRunState()
        )
    }
}
