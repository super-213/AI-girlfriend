import Foundation

actor MemoryAgentSession: AgentSession {
    nonisolated let id: String
    private var items: [AgentItem]
    private var runState: RunState?

    init(id: String = UUID().uuidString, items: [AgentItem] = []) {
        self.id = id
        self.items = items
    }

    func loadItems() -> [AgentItem] { items }

    func append(_ items: [AgentItem]) {
        self.items.append(contentsOf: items)
    }

    func replaceItems(_ items: [AgentItem]) {
        self.items = items
    }

    func loadRunState() -> RunState? { runState }

    func saveRunState(_ state: RunState?) {
        runState = state
    }
}
