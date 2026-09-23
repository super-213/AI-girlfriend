import Foundation

public actor MemoryAgentSession: AgentSession {
    public nonisolated let id: String
    private var items: [AgentItem]
    private var runState: RunState?

    public init(
        id: String = UUID().uuidString,
        items: [AgentItem] = [],
        runState: RunState? = nil
    ) {
        self.id = id
        self.items = items
        self.runState = runState
    }

    public func loadItems() -> [AgentItem] { items }

    public func append(_ items: [AgentItem]) {
        self.items.append(contentsOf: items)
    }

    public func replaceItems(_ items: [AgentItem]) {
        self.items = items
    }

    public func loadRunState() -> RunState? { runState }

    public func saveRunState(_ state: RunState?) {
        runState = state
    }
}
