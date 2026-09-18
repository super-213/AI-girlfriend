import Foundation

struct AgentSessionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var sessionID: String
    var createdAt: Date
    var updatedAt: Date
    var agentID: String
    var providerConfigurationID: String
    var items: [AgentItem]
    var pendingRunState: RunState?

    init(
        schemaVersion: Int = AgentSessionSnapshot.currentSchemaVersion,
        sessionID: String = UUID().uuidString,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        agentID: String = "desktop-companion",
        providerConfigurationID: String = "default",
        items: [AgentItem] = [],
        pendingRunState: RunState? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.agentID = agentID
        self.providerConfigurationID = providerConfigurationID
        self.items = items
        self.pendingRunState = pendingRunState
    }

    init(
        legacyMessages: [AgentMessage],
        sessionID: String = UUID().uuidString,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        agentID: String = "desktop-companion",
        providerConfigurationID: String = "legacy"
    ) {
        self.init(
            sessionID: sessionID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            agentID: agentID,
            providerConfigurationID: providerConfigurationID,
            items: AgentItemLegacyCodec.items(from: legacyMessages)
        )
    }

    var legacyMessages: [AgentMessage] {
        AgentItemLegacyCodec.messages(from: items)
    }
}
