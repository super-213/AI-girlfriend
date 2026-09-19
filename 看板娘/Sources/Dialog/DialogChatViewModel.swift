//
//  DialogChatViewModel.swift
//  看板娘
//
//  对话窗口的状态管理、历史会话与上下文聊天请求
//

import Combine
import Foundation
import SwiftUI

enum DialogConversationKind: String, Codable {
    case standard
    case pet
}

struct DialogMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
        case tool
    }

    let id: UUID
    let role: Role
    var content: String
    var attachments: [LocalFileAttachment]
    var artifacts: [DialogArtifact]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [LocalFileAttachment] = [],
        artifacts: [DialogArtifact] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey { case id, role, content, attachments, artifacts }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([LocalFileAttachment].self, forKey: .attachments) ?? []
        artifacts = try container.decodeIfPresent([DialogArtifact].self, forKey: .artifacts) ?? []
    }
}

struct QueuedDialogMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let instruction: String
    let invocation: AgentInvocation?
    let attachments: [LocalFileAttachment]

    init(
        id: UUID = UUID(),
        content: String,
        instruction: String? = nil,
        invocation: AgentInvocation? = nil,
        attachments: [LocalFileAttachment] = []
    ) {
        self.id = id
        self.content = content
        self.instruction = instruction ?? content
        self.invocation = invocation
        self.attachments = attachments
    }
}

struct DialogProject: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    let sourceDirectory: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sourceDirectory: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceDirectory = URL(fileURLWithPath: sourceDirectory).standardizedFileURL.path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sourceFolderName: String {
        let folderName = URL(fileURLWithPath: sourceDirectory).lastPathComponent
        return folderName.isEmpty ? sourceDirectory : folderName
    }
}

struct DialogConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [DialogMessage]
    var agentSession: AgentSessionSnapshot
    let createdAt: Date
    var updatedAt: Date
    var kind: DialogConversationKind
    var projectID: UUID?

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        messages: [DialogMessage] = [],
        agentSession: AgentSessionSnapshot? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        kind: DialogConversationKind = .standard,
        projectID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        let resolvedSession = agentSession ?? AgentSessionSnapshot(
            sessionID: id.uuidString,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        self.agentSession = resolvedSession
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.projectID = projectID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, messages, agentHistory, agentSession, createdAt, updatedAt, kind, projectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([DialogMessage].self, forKey: .messages)
        let legacyHistory = try container.decodeIfPresent(
            [AgentMessage].self,
            forKey: .agentHistory
        ) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        agentSession = try container.decodeIfPresent(
            AgentSessionSnapshot.self,
            forKey: .agentSession
        ) ?? AgentSessionSnapshot(
            legacyMessages: legacyHistory,
            sessionID: id.uuidString,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        kind = try container.decodeIfPresent(DialogConversationKind.self, forKey: .kind) ?? .standard
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(messages, forKey: .messages)
        try container.encode(agentSession, forKey: .agentSession)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(projectID, forKey: .projectID)
    }
}

@MainActor
final class DialogConversationStore {
    struct Change {
        let conversations: [DialogConversation]
        let projects: [DialogProject]
        let sourceID: UUID
    }

    static let shared = DialogConversationStore(defaults: .standard)
    static let conversationsStorageKey = "dialog.conversations.v1"
    static let projectsStorageKey = "dialog.projects.v1"

    private(set) var conversations: [DialogConversation]
    private(set) var projects: [DialogProject]
    let changes = PassthroughSubject<Change, Never>()

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        projects = Self.loadProjects(from: defaults)
        let projectIDs = Set(projects.map(\.id))
        conversations = Self.load(from: defaults).map { conversation in
            guard let projectID = conversation.projectID,
                  !projectIDs.contains(projectID) else { return conversation }
            var detached = conversation
            detached.projectID = nil
            return detached
        }
    }

    var petConversation: DialogConversation? {
        conversations.first(where: { $0.kind == .pet })
    }

    func replaceAll(_ conversations: [DialogConversation], sourceID: UUID) {
        save(conversations, projects: projects, sourceID: sourceID)
    }

    func replaceWorkspace(
        conversations: [DialogConversation],
        projects: [DialogProject],
        sourceID: UUID
    ) {
        save(conversations, projects: projects, sourceID: sourceID)
    }

    func upsertPetConversation(_ conversation: DialogConversation, sourceID: UUID) {
        var updated = conversations.filter { $0.kind != .pet && $0.id != conversation.id }
        updated.append(conversation)
        save(updated, projects: projects, sourceID: sourceID)
    }

    func deleteConversation(_ conversationID: UUID, sourceID: UUID) {
        save(
            conversations.filter { $0.id != conversationID },
            projects: projects,
            sourceID: sourceID
        )
    }

    private func save(
        _ conversations: [DialogConversation],
        projects: [DialogProject],
        sourceID: UUID
    ) {
        let normalized = Self.normalized(conversations)
        let normalizedProjects = Self.normalized(projects)
        guard let data = try? JSONEncoder().encode(normalized),
              let projectData = try? JSONEncoder().encode(normalizedProjects) else { return }
        self.conversations = normalized
        self.projects = normalizedProjects
        defaults.set(data, forKey: Self.conversationsStorageKey)
        defaults.set(projectData, forKey: Self.projectsStorageKey)
        changes.send(Change(
            conversations: normalized,
            projects: normalizedProjects,
            sourceID: sourceID
        ))
    }

    private static func load(from defaults: UserDefaults) -> [DialogConversation] {
        guard let data = defaults.data(forKey: conversationsStorageKey),
              let decoded = try? JSONDecoder().decode([DialogConversation].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    private static func loadProjects(from defaults: UserDefaults) -> [DialogProject] {
        guard let data = defaults.data(forKey: projectsStorageKey),
              let decoded = try? JSONDecoder().decode([DialogProject].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    private static func normalized(_ conversations: [DialogConversation]) -> [DialogConversation] {
        let regular = conversations.filter { $0.kind == .standard }
        let newestPet = conversations
            .filter { $0.kind == .pet }
            .max(by: { $0.updatedAt < $1.updatedAt })
        return (regular + [newestPet].compactMap { $0 })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private static func normalized(_ projects: [DialogProject]) -> [DialogProject] {
        var seen = Set<UUID>()
        return projects
            .filter { seen.insert($0.id).inserted }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }
}

struct DialogCacheStatus: Equatable {
    let provider: String
    let model: String
    let metrics: AgentCacheMetrics?

    var cacheHitRatio: Double? {
        metrics?.cacheHitRatio
    }

    static func load(from defaults: UserDefaults) -> DialogCacheStatus {
        let provider = defaults.string(forKey: "provider") ?? ModelProvider.zhipu.rawValue
        let model = defaults.string(forKey: "aiModel") ?? "glm-4v-flash"
        let key = AgentCacheMetricsStore.metricKey(provider: provider, model: model)
        return DialogCacheStatus(
            provider: provider,
            model: model,
            metrics: AgentCacheMetricsStore.load(defaults: defaults)[key]
        )
    }
}

@MainActor
final class DialogChatViewModel: ObservableObject {
    @Published private(set) var conversations: [DialogConversation]
    @Published private(set) var projects: [DialogProject]
    @Published private(set) var selectedConversationID: UUID
    @Published var messages: [DialogMessage]
    @Published var inputText: String = ""
    @Published private(set) var pendingAttachments: [LocalFileAttachment] = []
    @Published private(set) var queuedMessages: [QueuedDialogMessage] = []
    @Published var isRequesting: Bool = false
    @Published var showToolConfirmation: Bool = false
    @Published var pendingToolSummary: String = ""
    @Published var isExecutingTool: Bool = false
    @Published private(set) var isCompactingContext: Bool = false
    @Published private(set) var cacheStatus: DialogCacheStatus
    @Published private(set) var invocationOptions: [AgentInvocationOption]

    private static let selectedConversationStorageKey = "dialog.selectedConversation.v1"

    private let defaults: UserDefaults
    private let agentRuntime: AgentRuntime
    private let conversationStore: DialogConversationStore
    private let conversationStoreSourceID = UUID()
    private var conversationStoreCancellable: AnyCancellable?
    private var agentRuntimeEventTask: Task<Void, Never>?
    private lazy var streamTextCoalescer = StreamingTextCoalescer { [weak self] text in
        guard let self, let id = self.activeAssistantID else { return }
        self.appendAssistantChunk(text, to: id)
    }
    private var activeAssistantID: UUID?

    var selectedConversationTitle: String {
        conversations.first(where: { $0.id == selectedConversationID })?.title ?? "对话"
    }

    var selectedProject: DialogProject? {
        guard let projectID = conversations
            .first(where: { $0.id == selectedConversationID })?
            .projectID else { return nil }
        return projects.first(where: { $0.id == projectID })
    }

    var isBusy: Bool {
        isRequesting || isExecutingTool
    }

    init(
        defaults: UserDefaults = .standard,
        agentRuntime: AgentRuntime? = nil,
        conversationStore: DialogConversationStore? = nil
    ) {
        self.defaults = defaults
        let resolvedConversationStore = conversationStore
            ?? (defaults === UserDefaults.standard
                ? DialogConversationStore.shared
                : DialogConversationStore(defaults: defaults))
        self.conversationStore = resolvedConversationStore
        if let agentRuntime {
            self.agentRuntime = agentRuntime
        } else {
            let apiManager = APIManager()
            self.agentRuntime = AgentRuntime(apiManager: apiManager) {
                let style = PetConversationStyleStore.activeStyle(defaults: defaults)
                return apiManager.systemPromptContent(basePrompt: style.systemPrompt)
            }
        }

        let restored = resolvedConversationStore.conversations
        let restoredProjects = resolvedConversationStore.projects
        let initialConversations = restored.isEmpty ? [DialogConversation()] : restored
        let storedSelection = defaults.string(forKey: Self.selectedConversationStorageKey)
            .flatMap(UUID.init(uuidString:))
        let initialSelection = initialConversations.first(where: { $0.id == storedSelection })?.id
            ?? initialConversations.sorted(by: { $0.updatedAt > $1.updatedAt }).first!.id
        let initialConversation = initialConversations.first(where: { $0.id == initialSelection })!

        conversations = initialConversations
        projects = restoredProjects
        selectedConversationID = initialSelection
        messages = initialConversation.messages
        cacheStatus = DialogCacheStatus.load(from: defaults)
        invocationOptions = AgentInvocationCatalog.options(defaults: defaults)

        configureAgentRuntime()
        self.agentRuntime.restoreSession(initialConversation.agentSession)
        updateAgentWorkspaceContext()
        conversationStoreCancellable = resolvedConversationStore.changes
            .sink { [weak self] change in
                guard let self, change.sourceID != self.conversationStoreSourceID else { return }
                self.applyConversationStoreChange(
                    change.conversations,
                    projects: change.projects
                )
            }
    }

    deinit {
        agentRuntimeEventTask?.cancel()
    }

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }
        let submission = AgentInvocationParser.submission(
            from: trimmed,
            options: invocationOptions
        )

        inputText = ""
        let attachments = pendingAttachments
        pendingAttachments = []
        if isBusy {
            queuedMessages.append(QueuedDialogMessage(
                content: submission.visibleText,
                instruction: submission.instruction,
                invocation: submission.invocation,
                attachments: attachments
            ))
            return
        }

        sendImmediately(
            submission.visibleText,
            instruction: submission.instruction,
            invocation: submission.invocation,
            attachments: attachments
        )
    }

    func deleteQueuedMessage(_ messageID: UUID) {
        queuedMessages.removeAll(where: { $0.id == messageID })
    }

    func attachFiles(_ urls: [URL]) {
        let incoming = urls.filter(\.isFileURL).map { LocalFileAttachment(url: $0) }
        guard !incoming.isEmpty else { return }
        AgentFileAccessStore.shared.grantSessionAccess(to: urls)
        let known = Set(pendingAttachments.map(\.path))
        pendingAttachments.append(contentsOf: incoming.filter { !known.contains($0.path) })
    }

    func removeAttachment(_ id: UUID) { pendingAttachments.removeAll { $0.id == id } }
    func clearAttachments() { pendingAttachments.removeAll() }

    func attachResultFiles(_ paths: [String]) {
        attachFiles(paths.map { URL(fileURLWithPath: $0) })
    }

    private func sendImmediately(
        _ text: String,
        instruction: String,
        invocation: AgentInvocation?,
        attachments: [LocalFileAttachment]
    ) {
        let visibleText = text.isEmpty ? "请分析这些附件" : text
        messages.append(DialogMessage(role: .user, content: visibleText, attachments: attachments))
        let modelInstruction = instruction.isEmpty ? "请分析这些附件" : instruction
        let prompt = FileAttachmentPromptBuilder.prompt(
            userInstruction: modelInstruction,
            attachments: attachments
        )
        // `AgentRunner` starts asynchronously. Mark the turn busy before handing it off so
        // messages submitted in the same main-actor turn are queued instead of racing `send`.
        isRequesting = true
        agentRuntime.send(
            prompt,
            imagePaths: attachments.filter(\.isImage).map(\.path),
            explicitInvocation: invocation
        )
        synchronizeSelectedConversation(persist: true)
    }

    func refreshInvocationOptions() {
        invocationOptions = AgentInvocationCatalog.options(defaults: defaults)
    }

    func applyInvocationOption(_ option: AgentInvocationOption) {
        inputText = AgentInvocationParser.replacingQuery(in: inputText, with: option)
    }

    func startNewConversation(in projectID: UUID? = nil) {
        guard !isBusy else { return }

        synchronizeSelectedConversation(persist: true, updateTimestamp: false)
        let selectedConversation = conversations.first(where: { $0.id == selectedConversationID })
        if messages.isEmpty, selectedConversation?.projectID == projectID {
            inputText = ""
            pendingAttachments = []
            return
        }

        streamTextCoalescer.reset()
        let conversation = DialogConversation(projectID: projectID)
        conversations.append(conversation)
        selectedConversationID = conversation.id
        messages = []
        inputText = ""
        pendingAttachments = []
        activeAssistantID = nil
        agentRuntime.startNewConversation()
        updateAgentWorkspaceContext()
        persistConversations()
    }

    @discardableResult
    func createProject(name: String, sourceDirectory: URL) -> Bool {
        guard !isBusy else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = sourceDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard !trimmedName.isEmpty,
              FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !projects.contains(where: { $0.sourceDirectory == directory.path }) else { return false }

        synchronizeSelectedConversation(persist: false, updateTimestamp: false)
        if let index = conversations.firstIndex(where: { $0.id == selectedConversationID }),
           conversations[index].kind == .standard,
           conversations[index].projectID == nil,
           conversations[index].messages.isEmpty,
           conversations[index].agentSession.items.isEmpty {
            conversations.remove(at: index)
        }
        let project = DialogProject(name: trimmedName, sourceDirectory: directory.path)
        let conversation = DialogConversation(projectID: project.id)
        projects.append(project)
        conversations.append(conversation)
        streamTextCoalescer.reset()
        selectedConversationID = conversation.id
        messages = []
        inputText = ""
        pendingAttachments = []
        queuedMessages = []
        activeAssistantID = nil
        showToolConfirmation = false
        pendingToolSummary = ""
        agentRuntime.startNewConversation()
        updateAgentWorkspaceContext()
        persistConversations()
        return true
    }

    func deleteProject(_ projectID: UUID) {
        guard !isBusy,
              projects.contains(where: { $0.id == projectID }) else { return }

        let removedSelectedConversation = conversations
            .first(where: { $0.id == selectedConversationID })?
            .projectID == projectID
        projects.removeAll(where: { $0.id == projectID })
        conversations.removeAll(where: { $0.projectID == projectID })
        if conversations.isEmpty {
            conversations = [DialogConversation()]
        }

        if removedSelectedConversation {
            let next = conversations.max(by: { $0.updatedAt < $1.updatedAt })!
            streamTextCoalescer.reset()
            selectedConversationID = next.id
            messages = next.messages
            inputText = ""
            pendingAttachments = []
            queuedMessages = []
            activeAssistantID = nil
            agentRuntime.restoreSession(next.agentSession)
            updateAgentWorkspaceContext()
        }
        persistConversations()
    }

    func selectConversation(_ conversationID: UUID) {
        guard !isBusy,
              conversationID != selectedConversationID,
              let conversation = conversations.first(where: { $0.id == conversationID }) else { return }

        synchronizeSelectedConversation(persist: false, updateTimestamp: false)
        streamTextCoalescer.reset()
        selectedConversationID = conversationID
        messages = conversation.messages
        inputText = ""
        pendingAttachments = []
        activeAssistantID = nil
        showToolConfirmation = false
        pendingToolSummary = ""
        agentRuntime.restoreSession(conversation.agentSession)
        updateAgentWorkspaceContext()
        persistConversations()
    }

    func deleteConversation(_ conversationID: UUID) {
        guard !isBusy, let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        let deletedConversation = conversations[index]
        conversations.remove(at: index)

        if selectedConversationID == conversationID {
            let next: DialogConversation
            if let projectID = deletedConversation.projectID,
               projects.contains(where: { $0.id == projectID }) {
                if let projectConversation = conversations
                    .filter({ $0.projectID == projectID })
                    .max(by: { $0.updatedAt < $1.updatedAt }) {
                    next = projectConversation
                } else {
                    let replacement = DialogConversation(projectID: projectID)
                    conversations.append(replacement)
                    next = replacement
                }
            } else {
                if conversations.isEmpty {
                    conversations.append(DialogConversation())
                }
                next = conversations.max(by: { $0.updatedAt < $1.updatedAt })!
            }
            streamTextCoalescer.reset()
            selectedConversationID = next.id
            messages = next.messages
            inputText = ""
            pendingAttachments = []
            activeAssistantID = nil
            agentRuntime.restoreSession(next.agentSession)
            updateAgentWorkspaceContext()
        }
        persistConversations()
    }

    func stopGenerating() {
        guard isRequesting, !isExecutingTool else { return }
        streamTextCoalescer.flush()
        agentRuntime.cancel()
        isRequesting = false
        isExecutingTool = false
        isCompactingContext = false
        showToolConfirmation = false
        pendingToolSummary = ""
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
        appendAssistantStatus("已停止生成。")
        refreshCacheStatus()
        synchronizeSelectedConversation(persist: true)
        sendNextQueuedMessageIfPossible()
    }

    func refreshCacheStatus() {
        cacheStatus = DialogCacheStatus.load(from: defaults)
    }

    func approvePendingTool() {
        showToolConfirmation = false
        pendingToolSummary = ""
        agentRuntime.approvePendingTool()
    }

    func declinePendingTool() {
        showToolConfirmation = false
        pendingToolSummary = ""
        agentRuntime.declinePendingTool()
    }

    private func appendAssistantChunk(_ chunk: String, to messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].content += chunk
    }

    private func fillEmptyAssistantMessage(_ text: String) {
        guard let messageID = activeAssistantID,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].content.isEmpty else { return }
        messages[index].content = text
    }

    private func configureAgentRuntime() {
        agentRuntimeEventTask?.cancel()
        agentRuntimeEventTask = Task { @MainActor [weak self, agentRuntime] in
            for await event in agentRuntime.events {
                guard let self else { return }
                self.consumeAgentRuntimeEvent(event)
            }
        }
    }

    private func consumeAgentRuntimeEvent(_ event: AgentRuntimeEvent) {
        switch event {
        case .sessionUpdated(let snapshot):
            guard let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
                return
            }
            conversations[index].agentSession = snapshot
        case .run(.contextCompactionStarted):
            streamTextCoalescer.flush()
            isRequesting = true
            isExecutingTool = false
            isCompactingContext = true
        case .run(.modelStarted):
            streamTextCoalescer.flush()
            let id = UUID()
            activeAssistantID = id
            isRequesting = true
            isExecutingTool = false
            isCompactingContext = false
            messages.append(DialogMessage(id: id, role: .assistant, content: ""))
        case .run(.textDelta(let chunk)):
            streamTextCoalescer.append(chunk)
        case .run(.toolCallStarted(let call)):
            streamTextCoalescer.flush()
            isExecutingTool = true
            fillEmptyAssistantMessage("正在调用工具：\(call.name)…")
        case .run(.toolCallCompleted(let item)):
            isExecutingTool = false
            let result = item.displayExecutionResult
            if result.isError {
                messages.append(DialogMessage(
                    role: .tool,
                    content: "工具 \(item.toolName) 执行失败：\(result.content)"
                ))
            } else if let artifact = Self.artifact(toolName: item.toolName, result: result.content) {
                messages.append(DialogMessage(role: .tool, content: "", artifacts: [artifact]))
            } else if defaults.bool(forKey: AgentWorkspaceSettings.showToolAuditInConversationKey) {
                messages.append(DialogMessage(role: .tool, content: "工具 \(item.toolName) 已完成"))
            }
        case .run(.approvalRequired(let interruption)):
            streamTextCoalescer.flush()
            isRequesting = true
            isExecutingTool = false
            pendingToolSummary = interruption.summary
            fillEmptyAssistantMessage("请求调用工具：\(interruption.toolCall.name)")
            showToolConfirmation = true
            synchronizeSelectedConversation(persist: true)
        case .run(.runCompleted):
            streamTextCoalescer.flush()
            isRequesting = false
            isExecutingTool = false
            isCompactingContext = false
            fillEmptyAssistantMessage("（模型没有返回文本）")
            refreshCacheStatus()
            synchronizeSelectedConversation(persist: true)
            sendNextQueuedMessageIfPossible()
        case .run(.runFailed(let error)):
            streamTextCoalescer.flush()
            isRequesting = false
            isExecutingTool = false
            isCompactingContext = false
            showToolConfirmation = false
            pendingToolSummary = ""
            fillEmptyAssistantMessage("请求失败：\(error.localizedDescription)")
            refreshCacheStatus()
            synchronizeSelectedConversation(persist: true)
            sendNextQueuedMessageIfPossible()
        case .run:
            break
        }
    }

    private func sendNextQueuedMessageIfPossible() {
        guard !isBusy, !queuedMessages.isEmpty else { return }
        let next = queuedMessages.removeFirst()
        sendImmediately(
            next.content,
            instruction: next.instruction,
            invocation: next.invocation,
            attachments: next.attachments
        )
    }

    private func appendAssistantStatus(_ status: String) {
        messages.append(DialogMessage(role: .assistant, content: status))
    }

    private func synchronizeSelectedConversation(
        persist: Bool,
        updateTimestamp: Bool = true
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else { return }

        conversations[index].messages = messages
        conversations[index].agentSession = agentRuntime.sessionSnapshot
        conversations[index].title = conversations[index].kind == .pet
            ? "桌宠对话"
            : title(for: messages)
        if updateTimestamp {
            conversations[index].updatedAt = .now
            if let projectID = conversations[index].projectID,
               let projectIndex = projects.firstIndex(where: { $0.id == projectID }) {
                projects[projectIndex].updatedAt = conversations[index].updatedAt
            }
        }
        if persist {
            persistConversations()
        }
    }

    private func title(for messages: [DialogMessage]) -> String {
        guard let firstPrompt = messages.first(where: { $0.role == .user })?.content else {
            return "新对话"
        }
        let singleLine = firstPrompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > 28 else { return singleLine }
        return String(singleLine.prefix(28)) + "…"
    }

    private func persistConversations() {
        conversationStore.replaceWorkspace(
            conversations: conversations,
            projects: projects,
            sourceID: conversationStoreSourceID
        )
        defaults.set(selectedConversationID.uuidString, forKey: Self.selectedConversationStorageKey)
    }

    private func applyConversationStoreChange(
        _ storedConversations: [DialogConversation],
        projects storedProjects: [DialogProject]
    ) {
        // Keep an in-flight selection stable. In particular, the pet-side
        // expiration timer may fire while this window is actively continuing
        // the shared pet conversation; completion below will publish the
        // renewed timestamp and recreate that still-active conversation.
        if isBusy {
            if storedConversations.contains(where: { $0.id == selectedConversationID }) {
                conversations = storedConversations
                projects = storedProjects
            }
            return
        }

        if storedConversations.isEmpty {
            let conversation = DialogConversation()
            conversations = [conversation]
            projects = storedProjects
            selectedConversationID = conversation.id
            messages = []
            inputText = ""
            pendingAttachments = []
            activeAssistantID = nil
            agentRuntime.startNewConversation()
            updateAgentWorkspaceContext()
            persistConversations()
            return
        }

        conversations = storedConversations
        projects = storedProjects
        let selection = storedConversations.first(where: { $0.id == selectedConversationID })
            ?? storedConversations.max(by: { $0.updatedAt < $1.updatedAt })!
        streamTextCoalescer.reset()
        selectedConversationID = selection.id
        messages = selection.messages
        inputText = ""
        pendingAttachments = []
        activeAssistantID = nil
        showToolConfirmation = false
        pendingToolSummary = ""
        agentRuntime.restoreSession(selection.agentSession)
        updateAgentWorkspaceContext()
        defaults.set(selectedConversationID.uuidString, forKey: Self.selectedConversationStorageKey)
    }

    private func updateAgentWorkspaceContext() {
        guard let project = selectedProject else {
            agentRuntime.additionalSystemContext = nil
            agentRuntime.projectID = nil
            agentRuntime.workspacePath = nil
            return
        }
        AgentFileAccessStore.shared.grantSessionAccess(to: [
            URL(fileURLWithPath: project.sourceDirectory, isDirectory: true)
        ])
        agentRuntime.projectID = project.id
        agentRuntime.workspacePath = project.sourceDirectory
        agentRuntime.additionalSystemContext = """

        ## 当前项目工作区
        项目名称：\(project.name)
        项目根目录：\(project.sourceDirectory)
        用户已将该目录设为当前项目的源文件夹，并授权你为完成项目任务读取它。
        将该目录视为当前工作目录；当用户使用“这个项目”、“项目代码”或相对路径时，都从该根目录解析。
        调用文件工具时使用该目录下的绝对路径；执行 Shell 命令时将 working_directory 设为该目录。
        """
    }

    private static func artifact(toolName: String, result: String) -> DialogArtifact? {
        guard toolName == "search_files",
              let data = result.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["results"] as? [[String: Any]] else { return nil }
        let files = values.compactMap { value -> AgentFileResult? in
            guard let path = value["path"] as? String else { return nil }
            return AgentFileResult(
                name: value["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                isDirectory: value["is_directory"] as? Bool ?? false,
                sizeBytes: value["size_bytes"] as? Int,
                modifiedAt: value["modified_at"] as? String
            )
        }
        return DialogArtifact(kind: .fileResults, title: "找到 \(files.count) 个结果", files: files)
    }
}
