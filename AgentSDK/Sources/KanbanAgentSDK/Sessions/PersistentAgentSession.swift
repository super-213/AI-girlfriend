import Foundation

public actor PersistentAgentSession: AgentSession {
    public nonisolated let id: String
    public nonisolated let fileURL: URL
    private var document: AgentSessionSnapshot

    public init(
        fileURL: URL,
        id: String = UUID().uuidString,
        agentID: String = "desktop-companion",
        providerConfigurationID: String = "default"
    ) throws {
        self.fileURL = fileURL.standardizedFileURL
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            let data = try Data(contentsOf: self.fileURL)
            let decoded = try JSONDecoder().decode(AgentSessionSnapshot.self, from: data)
            guard decoded.schemaVersion == AgentSessionSnapshot.currentSchemaVersion else {
                throw AgentError.sessionFailure("不支持的 Session 版本 \(decoded.schemaVersion)")
            }
            self.id = decoded.sessionID
            document = decoded
        } else {
            self.id = id
            document = AgentSessionSnapshot(
                sessionID: id,
                agentID: agentID,
                providerConfigurationID: providerConfigurationID
            )
        }
    }

    public func loadItems() -> [AgentItem] { document.items }

    public func append(_ items: [AgentItem]) throws {
        document.items.append(contentsOf: items)
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    public func replaceItems(_ items: [AgentItem]) throws {
        document.items = items
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    public func loadRunState() -> RunState? { document.pendingRunState }

    public func saveRunState(_ state: RunState?) throws {
        document.pendingRunState = state
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    public func snapshot() -> AgentSessionSnapshot { document }

    private func persistCurrentDocument() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // `document` intentionally remains updated so a storage failure never erases
            // the in-memory result. Callers receive the failure and can retry persistence.
            throw AgentError.sessionFailure(error.localizedDescription)
        }
    }
}
