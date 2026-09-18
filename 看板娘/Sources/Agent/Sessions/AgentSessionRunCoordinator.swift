import Foundation

actor AgentSessionRunCoordinator {
    static let shared = AgentSessionRunCoordinator()
    private var activeRunBySessionID: [String: UUID] = [:]

    func acquire(sessionID: String, runID: UUID) -> Bool {
        guard activeRunBySessionID[sessionID] == nil else { return false }
        activeRunBySessionID[sessionID] = runID
        return true
    }

    func release(sessionID: String, runID: UUID) {
        guard activeRunBySessionID[sessionID] == runID else { return }
        activeRunBySessionID.removeValue(forKey: sessionID)
    }
}
