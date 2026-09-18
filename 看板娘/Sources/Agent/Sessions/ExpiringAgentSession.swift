import Foundation

actor ExpiringAgentSession: AgentSession {
    nonisolated let id: String
    private var items: [AgentItem]
    private var runState: RunState?
    private var lastAccessAt: Date?
    private let timeout: TimeInterval?
    private let now: @Sendable () -> Date

    init(
        id: String = UUID().uuidString,
        items: [AgentItem] = [],
        runState: RunState? = nil,
        timeout: TimeInterval?,
        lastAccessAt: Date? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.id = id
        self.items = items
        self.runState = runState
        self.timeout = timeout
        self.lastAccessAt = lastAccessAt ?? (items.isEmpty ? nil : now())
        self.now = now
    }

    func loadItems() -> [AgentItem] {
        expireIfNeeded()
        return items
    }

    func append(_ items: [AgentItem]) {
        expireIfNeeded()
        self.items.append(contentsOf: items)
        touch()
    }

    func replaceItems(_ items: [AgentItem]) {
        expireIfNeeded()
        self.items = items
        touch()
    }

    func loadRunState() -> RunState? {
        expireIfNeeded()
        return runState
    }

    func saveRunState(_ state: RunState?) {
        expireIfNeeded()
        runState = state
        touch()
    }

    func remainingLifetime() -> TimeInterval? {
        expireIfNeeded()
        guard let timeout, let lastAccessAt, !items.isEmpty else { return nil }
        return max(timeout - now().timeIntervalSince(lastAccessAt), 0)
    }

    private func touch() {
        lastAccessAt = items.isEmpty && runState == nil ? nil : now()
    }

    private func expireIfNeeded() {
        guard let timeout, let lastAccessAt,
              now().timeIntervalSince(lastAccessAt) >= timeout else { return }
        items.removeAll()
        runState = nil
        self.lastAccessAt = nil
    }
}
