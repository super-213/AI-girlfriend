import Foundation
import Testing
@testable import 看板娘

struct DialogMessageQueueTests {
    @MainActor
    private final class DeferredModelClient: AgentModelClient {
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
    func busyConversationQueuesMessagesAndSendsThemInOrder() async throws {
        try await withViewModel { viewModel, client in
            viewModel.send("第一条")
            viewModel.send("第二条")
            viewModel.send("第三条")

            await waitUntil { client.requests.count == 1 }

            #expect(viewModel.isRequesting)
            #expect(viewModel.inputText.isEmpty)
            #expect(viewModel.queuedMessages.map(\.content) == ["第二条", "第三条"])
            #expect(client.requests.count == 1)

            client.complete(with: "回复一")

            await waitUntil { client.requests.count == 2 }

            #expect(client.requests.count == 2)
            #expect(client.requests[1].last == .user("第二条"))
            #expect(viewModel.queuedMessages.map(\.content) == ["第三条"])

            client.complete(with: "回复二")

            await waitUntil { client.requests.count == 3 }

            #expect(client.requests.count == 3)
            #expect(client.requests[2].last == .user("第三条"))
            #expect(viewModel.queuedMessages.isEmpty)

            client.complete(with: "回复三")
            await waitUntil { !viewModel.isBusy }
            #expect(!viewModel.isBusy)
        }
    }

    @Test @MainActor
    func queuedMessageCanBeDeletedBeforeItIsSent() async throws {
        try await withViewModel { viewModel, client in
            viewModel.send("正在处理")
            viewModel.send("需要删除")
            viewModel.send("需要保留")

            await waitUntil { client.requests.count == 1 }

            let messageToDelete = try #require(viewModel.queuedMessages.first)
            viewModel.deleteQueuedMessage(messageToDelete.id)

            #expect(viewModel.queuedMessages.map(\.content) == ["需要保留"])

            client.complete(with: "当前回复")

            await waitUntil { client.requests.count == 2 }

            #expect(client.requests.count == 2)
            #expect(client.requests[1].last == .user("需要保留"))
        }
    }

    @Test @MainActor
    func stoppingCurrentResponseContinuesWithTheNextQueuedMessage() async throws {
        try await withViewModel { viewModel, client in
            viewModel.send("第一条")
            viewModel.send("停止后发送")

            await waitUntil { client.requests.count == 1 }

            viewModel.stopGenerating()

            await waitUntil { client.requests.count == 2 }

            #expect(client.requests.count == 2)
            #expect(client.requests[1].last == .user("停止后发送"))
            #expect(viewModel.queuedMessages.isEmpty)
            #expect(viewModel.isRequesting)
        }
    }

    @MainActor
    private func withViewModel(
        _ body: @MainActor (DialogChatViewModel, DeferredModelClient) async throws -> Void
    ) async throws {
        let suiteName = "DialogMessageQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let client = DeferredModelClient()
        let runtime = AgentRuntime(
            apiManager: client,
            registry: AgentToolRegistry(),
            systemPromptProvider: { "system" }
        )
        let viewModel = DialogChatViewModel(defaults: defaults, agentRuntime: runtime)
        try await body(viewModel, client)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待异步 Agent 状态超时")
    }
}
