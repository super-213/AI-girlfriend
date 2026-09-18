import Foundation
import Testing
@testable import 看板娘

struct DialogPetConversationTests {
    @MainActor
    private final class RecordingModelClient: AgentModelClient {
        private(set) var requests: [[AgentMessage]] = []
        private var onReceive: (@MainActor @Sendable (String) -> Void)?
        private var onComplete: (@MainActor @Sendable (AgentModelResponse) -> Void)?

        func sendAgentStreamRequest(
            messages: [AgentMessage],
            tools: [AgentToolDefinition],
            purpose: AgentRequestPurpose,
            onReceive: @escaping @MainActor @Sendable (String) -> Void,
            onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
            onError: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            requests.append(messages)
            self.onReceive = onReceive
            self.onComplete = onComplete
        }

        func cancelStreamRequest() {
            onReceive = nil
            onComplete = nil
        }

        func complete(with content: String) {
            let receive = onReceive
            let complete = onComplete
            onReceive = nil
            onComplete = nil
            receive?(content)
            complete?(AgentModelResponse(content: content, toolCalls: []))
        }
    }

    @Test @MainActor
    func storeKeepsOnlyTheNewestPetConversation() throws {
        try withStore { store, _ in
            let sourceID = UUID()
            let regular = DialogConversation(title: "普通对话")
            let olderPet = DialogConversation(
                title: "旧桌宠对话",
                updatedAt: Date(timeIntervalSince1970: 100),
                kind: .pet
            )
            let newerPet = DialogConversation(
                title: "新桌宠对话",
                updatedAt: Date(timeIntervalSince1970: 200),
                kind: .pet
            )

            store.replaceAll([regular, olderPet, newerPet], sourceID: sourceID)

            #expect(store.conversations.filter { $0.kind == .pet }.map(\.id) == [newerPet.id])
            #expect(store.conversations.contains(where: { $0.id == regular.id }))
        }
    }

    @Test @MainActor
    func fullDialogContinuesAndCanDeleteThePetConversation() throws {
        try withStore { store, defaults in
            let petConversation = DialogConversation(
                title: "桌宠对话",
                messages: [
                    DialogMessage(role: .user, content: "桌宠里的问题"),
                    DialogMessage(role: .assistant, content: "桌宠里的回复")
                ],
                agentHistory: [
                    .system("system"),
                    .user("桌宠里的问题"),
                    .assistant(content: "桌宠里的回复")
                ],
                kind: .pet
            )
            store.upsertPetConversation(petConversation, sourceID: UUID())

            let client = RecordingModelClient()
            let runtime = AgentRuntime(
                apiManager: client,
                registry: AgentToolRegistry(),
                systemPromptProvider: { "system" }
            )
            let viewModel = DialogChatViewModel(
                defaults: defaults,
                agentRuntime: runtime,
                conversationStore: store
            )

            #expect(viewModel.selectedConversationID == petConversation.id)
            #expect(viewModel.messages.map(\.content) == ["桌宠里的问题", "桌宠里的回复"])

            viewModel.send("在完整模式中继续")
            #expect(client.requests.first?.dropFirst().contains(.user("桌宠里的问题")) == true)
            #expect(client.requests.first?.last == .user("在完整模式中继续"))

            client.complete(with: "已接力")
            #expect(store.petConversation?.agentHistory.last == .assistant(content: "已接力"))

            viewModel.deleteConversation(petConversation.id)
            #expect(store.petConversation == nil)
            #expect(viewModel.conversations.count == 1)
            #expect(viewModel.conversations[0].kind == .standard)
        }
    }

    @Test
    func conversationsSavedBeforeKindsExistedDecodeAsStandard() throws {
        let conversation = DialogConversation(title: "旧对话")
        let encoded = try JSONEncoder().encode(conversation)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "kind")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DialogConversation.self, from: legacyData)

        #expect(decoded.kind == .standard)
    }

    @MainActor
    private func withStore(
        _ body: (DialogConversationStore, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "DialogPetConversationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(DialogConversationStore(defaults: defaults), defaults)
    }
}
