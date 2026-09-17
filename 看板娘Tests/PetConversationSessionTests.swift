import Foundation
import Testing
@testable import 看板娘

struct PetConversationSessionTests {
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
    func sessionKeepsHistoryUntilTheConfiguredTimeout() {
        let start = Date(timeIntervalSince1970: 1_000)
        let history: [AgentMessage] = [.system("system"), .user("first")]
        var session = PetConversationSession()
        session.record(history: history, at: start)

        let retained = session.historyForNextInput(
            at: start.addingTimeInterval(29 * 60 + 59),
            timeout: 30 * 60
        )

        #expect(retained == history)
    }

    @Test
    func sessionDestroysHistoryAtTheConfiguredTimeout() {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = PetConversationSession()
        session.record(history: [.system("system"), .user("first")], at: start)

        let expired = session.historyForNextInput(
            at: start.addingTimeInterval(30 * 60),
            timeout: 30 * 60
        )

        #expect(expired.isEmpty)
        #expect(session.lastConversationAt == nil)
    }

    @Test
    func sessionNeverExpiresWhenTimeoutIsDisabled() {
        let start = Date(timeIntervalSince1970: 1_000)
        let history: [AgentMessage] = [.system("system"), .user("first")]
        var session = PetConversationSession()
        session.record(history: history, at: start)

        let retained = session.historyForNextInput(
            at: start.addingTimeInterval(7 * 24 * 60 * 60),
            timeout: nil
        )

        #expect(retained == history)
    }
}
