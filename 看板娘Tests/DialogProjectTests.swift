import Foundation
import Testing
@testable import 看板娘

struct DialogProjectTests {
    @MainActor
    private final class RecordingModelClient: AgentModelClient {
        private(set) var requests: [[AgentMessage]] = []

        func sendAgentStreamRequest(
            messages: [AgentMessage],
            tools: [AgentToolDefinition],
            purpose: AgentRequestPurpose,
            onReceive: @escaping @MainActor @Sendable (String) -> Void,
            onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
            onError: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            requests.append(messages)
        }

        func cancelStreamRequest() {}
    }

    @Test @MainActor
    func creatingProjectPersistsWorkspaceAndScopesAgentContext() async throws {
        try await withWorkspace { viewModel, client, defaults, directory in
            #expect(viewModel.createProject(name: "演示项目", sourceDirectory: directory))
            let project = try #require(viewModel.projects.first)

            #expect(project.name == "演示项目")
            #expect(project.sourceDirectory == directory.standardizedFileURL.path)
            #expect(viewModel.selectedProject?.id == project.id)
            #expect(viewModel.conversations.count == 1)
            #expect(viewModel.conversations.contains {
                $0.id == viewModel.selectedConversationID && $0.projectID == project.id
            })

            viewModel.send("浏览项目代码")
            await waitUntil { !client.requests.isEmpty }
            let request = try #require(client.requests.first)
            #expect(request.first?.role == .system)
            #expect(request.first?.content?.contains("当前项目工作区") == true)
            #expect(request.first?.content?.contains(directory.standardizedFileURL.path) == true)
            #expect(request.last == .user("浏览项目代码"))

            let restoredStore = DialogConversationStore(defaults: defaults)
            #expect(restoredStore.projects.map(\.id) == [project.id])
            #expect(restoredStore.projects.first?.name == project.name)
            #expect(restoredStore.projects.first?.sourceDirectory == project.sourceDirectory)
            #expect(restoredStore.conversations.contains { $0.projectID == project.id })
        }
    }

    @Test @MainActor
    func removingProjectKeepsItsSourceDirectoryOnDisk() async throws {
        try await withWorkspace { viewModel, _, _, directory in
            #expect(viewModel.createProject(name: "不删源文件", sourceDirectory: directory))
            let projectID = try #require(viewModel.projects.first?.id)

            viewModel.deleteProject(projectID)

            #expect(viewModel.projects.isEmpty)
            #expect(!viewModel.conversations.contains { $0.projectID == projectID })
            #expect(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    @Test @MainActor
    func projectConversationCanCreateAnotherConversationInSameProject() async throws {
        try await withWorkspace { viewModel, _, _, directory in
            #expect(viewModel.createProject(name: "多对话", sourceDirectory: directory))
            let projectID = try #require(viewModel.selectedProject?.id)
            let firstConversationID = viewModel.selectedConversationID
            viewModel.send("first")

            viewModel.stopGenerating()
            viewModel.startNewConversation(in: projectID)

            #expect(viewModel.selectedConversationID != firstConversationID)
            #expect(viewModel.conversations.filter { $0.projectID == projectID }.count == 2)
            #expect(viewModel.selectedProject?.id == projectID)
        }
    }

    @Test @MainActor
    func deletingTheLastProjectConversationKeepsTheProjectActive() async throws {
        try await withWorkspace { viewModel, _, _, directory in
            #expect(viewModel.createProject(name: "保留项目", sourceDirectory: directory))
            let projectID = try #require(viewModel.selectedProject?.id)
            let conversationID = viewModel.selectedConversationID

            viewModel.deleteConversation(conversationID)

            #expect(viewModel.projects.contains { $0.id == projectID })
            #expect(viewModel.selectedConversationID != conversationID)
            #expect(viewModel.selectedProject?.id == projectID)
            #expect(viewModel.conversations.filter { $0.projectID == projectID }.count == 1)
            #expect(viewModel.messages.isEmpty)
        }
    }

    @MainActor
    private func withWorkspace(
        _ body: @MainActor (
            DialogChatViewModel,
            RecordingModelClient,
            UserDefaults,
            URL
        ) async throws -> Void
    ) async throws {
        let suiteName = "DialogProjectTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let client = RecordingModelClient()
        let runtime = AgentRuntime(
            apiManager: client,
            registry: AgentToolRegistry(),
            systemPromptProvider: { "system" }
        )
        let store = DialogConversationStore(defaults: defaults)
        let viewModel = DialogChatViewModel(
            defaults: defaults,
            agentRuntime: runtime,
            conversationStore: store
        )
        try await body(viewModel, client, defaults, directory)
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
