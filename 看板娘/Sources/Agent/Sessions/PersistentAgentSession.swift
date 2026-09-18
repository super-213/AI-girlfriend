import Foundation

actor PersistentAgentSession: AgentSession {
    nonisolated let id: String
    nonisolated let fileURL: URL
    private var document: AgentSessionSnapshot

    init(
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

    func loadItems() -> [AgentItem] { document.items }

    func append(_ items: [AgentItem]) throws {
        document.items.append(contentsOf: items)
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    func replaceItems(_ items: [AgentItem]) throws {
        document.items = items
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    func loadRunState() -> RunState? { document.pendingRunState }

    func saveRunState(_ state: RunState?) throws {
        document.pendingRunState = state
        document.updatedAt = .now
        try persistCurrentDocument()
    }

    func snapshot() -> AgentSessionSnapshot { document }

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
