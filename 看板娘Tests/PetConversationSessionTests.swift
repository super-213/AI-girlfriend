import Foundation
import Testing
@testable import 看板娘

struct ExpiringAgentSessionTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) { self.date = date }
        func now() -> Date { lock.withLock { date } }
        func advance(_ interval: TimeInterval) { lock.withLock { date.addTimeInterval(interval) } }
    }

    @Test
    func retentionDefaultsToThirtyMinutesAndSupportsNeverExpiring() {
        #expect(PetConversationRetention.minutes(storedValue: nil) == 30)
        #expect(PetConversationRetention.minutes(storedValue: 0) == 0)
    }

    @Test
    func retentionIsClampedToSupportedFiveMinuteSteps() {
        #expect(PetConversationRetention.normalized(1) == 5)
        #expect(PetConversationRetention.normalized(32) == 30)
        #expect(PetConversationRetention.normalized(33) == 35)
        #expect(PetConversationRetention.normalized(2_000) == 1_440)
    }

    @Test
    func sessionKeepsHistoryUntilTheConfiguredTimeout() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let history: [AgentMessage] = [.system("system"), .user("first")]
        let clock = Clock(start)
        let session = ExpiringAgentSession(
            items: AgentItemLegacyCodec.items(from: history),
            timeout: 30 * 60,
            lastAccessAt: start,
            now: clock.now
        )
        clock.advance(29 * 60 + 59)

        #expect(AgentItemLegacyCodec.messages(from: await session.loadItems()) == history)
    }

    @Test
    func sessionDestroysHistoryAtTheConfiguredTimeout() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = Clock(start)
        let session = ExpiringAgentSession(
            items: AgentItemLegacyCodec.items(from: [.system("system"), .user("first")]),
            timeout: 30 * 60,
            lastAccessAt: start,
            now: clock.now
        )
        clock.advance(30 * 60)

        #expect(await session.loadItems().isEmpty)
        #expect(await session.remainingLifetime() == nil)
    }

    @Test
    func sessionNeverExpiresWhenTimeoutIsDisabled() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let history: [AgentMessage] = [.system("system"), .user("first")]
        let clock = Clock(start)
        let session = ExpiringAgentSession(
            items: AgentItemLegacyCodec.items(from: history),
            timeout: nil,
            lastAccessAt: start,
            now: clock.now
        )
        clock.advance(7 * 24 * 60 * 60)

        #expect(AgentItemLegacyCodec.messages(from: await session.loadItems()) == history)
    }
}
