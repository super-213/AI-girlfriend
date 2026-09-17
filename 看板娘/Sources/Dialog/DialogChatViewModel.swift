//
//  DialogChatViewModel.swift
//  看板娘
//
//  对话窗口的状态管理、历史会话与上下文聊天请求
//

import Foundation
import SwiftUI

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
    let attachments: [LocalFileAttachment]

    init(id: UUID = UUID(), content: String, attachments: [LocalFileAttachment] = []) {
        self.id = id
        self.content = content
        self.attachments = attachments
    }
}

struct DialogConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [DialogMessage]
    var agentHistory: [AgentMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        messages: [DialogMessage] = [],
        agentHistory: [AgentMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.agentHistory = agentHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

    private static let conversationsStorageKey = "dialog.conversations.v1"
    private static let selectedConversationStorageKey = "dialog.selectedConversation.v1"

    private let defaults: UserDefaults
    private let agentRuntime: AgentRuntime
    private lazy var streamTextCoalescer = StreamingTextCoalescer { [weak self] text in
        guard let self, let id = self.activeAssistantID else { return }
        self.appendAssistantChunk(text, to: id)
    }
    private var activeAssistantID: UUID?

    var selectedConversationTitle: String {
        conversations.first(where: { $0.id == selectedConversationID })?.title ?? "对话"
    }

    var isBusy: Bool {
        isRequesting || isExecutingTool
    }

    init(defaults: UserDefaults = .standard, agentRuntime: AgentRuntime? = nil) {
        self.defaults = defaults
        if let agentRuntime {
            self.agentRuntime = agentRuntime
        } else {
            let apiManager = APIManager()
            self.agentRuntime = AgentRuntime(apiManager: apiManager) {
                let style = PetConversationStyleStore.activeStyle(defaults: defaults)
                return apiManager.systemPromptContent(basePrompt: style.systemPrompt)
            }
        }

        let restored = Self.loadConversations(from: defaults)
        let initialConversations = restored.isEmpty ? [DialogConversation()] : restored
        let storedSelection = defaults.string(forKey: Self.selectedConversationStorageKey)
            .flatMap(UUID.init(uuidString:))
        let initialSelection = initialConversations.first(where: { $0.id == storedSelection })?.id
            ?? initialConversations.sorted(by: { $0.updatedAt > $1.updatedAt }).first!.id
        let initialConversation = initialConversations.first(where: { $0.id == initialSelection })!

        conversations = initialConversations
        selectedConversationID = initialSelection
        messages = initialConversation.messages
        cacheStatus = DialogCacheStatus.load(from: defaults)

        configureAgentRuntime()
        self.agentRuntime.restoreConversation(initialConversation.agentHistory)
    }

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }

        inputText = ""
        let attachments = pendingAttachments
        pendingAttachments = []
        if isBusy {
            queuedMessages.append(QueuedDialogMessage(content: trimmed, attachments: attachments))
            return
        }

        sendImmediately(trimmed, attachments: attachments)
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

    private func sendImmediately(_ text: String, attachments: [LocalFileAttachment]) {
        let visibleText = text.isEmpty ? "请分析这些附件" : text
        messages.append(DialogMessage(role: .user, content: visibleText, attachments: attachments))
        let prompt = FileAttachmentPromptBuilder.prompt(userInstruction: visibleText, attachments: attachments)
        agentRuntime.send(prompt, imagePaths: attachments.filter(\.isImage).map(\.path))
        synchronizeSelectedConversation(persist: true)
    }

    func startNewConversation() {
        guard !isBusy else { return }

        synchronizeSelectedConversation(persist: true, updateTimestamp: false)
        if messages.isEmpty {
            inputText = ""
            pendingAttachments = []
            return
        }

        streamTextCoalescer.reset()
        let conversation = DialogConversation()
        conversations.append(conversation)
        selectedConversationID = conversation.id
        messages = []
        inputText = ""
        pendingAttachments = []
        activeAssistantID = nil
        agentRuntime.startNewConversation()
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
        agentRuntime.restoreConversation(conversation.agentHistory)
        persistConversations()
    }

    func deleteConversation(_ conversationID: UUID) {
        guard !isBusy, let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        conversations.remove(at: index)
        if conversations.isEmpty {
            conversations = [DialogConversation()]
        }

        if selectedConversationID == conversationID {
            let next = conversations.sorted(by: { $0.updatedAt > $1.updatedAt }).first!
            streamTextCoalescer.reset()
            selectedConversationID = next.id
            messages = next.messages
            inputText = ""
            pendingAttachments = []
            activeAssistantID = nil
            agentRuntime.restoreConversation(next.agentHistory)
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
        agentRuntime.onContextCompactionStarted = { [weak self] in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isRequesting = true
            self.isExecutingTool = false
            self.isCompactingContext = true
        }
        agentRuntime.onAssistantResponseStarted = { [weak self] in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            let id = UUID()
            self.activeAssistantID = id
            self.isRequesting = true
            self.isExecutingTool = false
            self.isCompactingContext = false
            self.messages.append(DialogMessage(id: id, role: .assistant, content: ""))
        }
        agentRuntime.onAssistantText = { [weak self] chunk in
            self?.streamTextCoalescer.append(chunk)
        }
        agentRuntime.onToolStarted = { [weak self] name in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isExecutingTool = true
            self.fillEmptyAssistantMessage("正在调用工具：\(name)…")
        }
        agentRuntime.onToolFinished = { [weak self] name, result in
            guard let self else { return }
            self.isExecutingTool = false
            if result.isError {
                self.messages.append(DialogMessage(
                    role: .tool,
                    content: "工具 \(name) 执行失败：\(result.content)"
                ))
            } else if let artifact = Self.artifact(toolName: name, result: result.content) {
                self.messages.append(DialogMessage(role: .tool, content: "", artifacts: [artifact]))
            } else if self.defaults.bool(forKey: AgentWorkspaceSettings.showToolAuditInConversationKey) {
                self.messages.append(DialogMessage(role: .tool, content: "工具 \(name) 已完成"))
            }
        }
        agentRuntime.onApprovalRequested = { [weak self] approval in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isExecutingTool = false
            self.pendingToolSummary = approval.summary
            self.fillEmptyAssistantMessage("请求调用工具：\(approval.toolName)")
            self.showToolConfirmation = true
        }
        agentRuntime.onCompleted = { [weak self] in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isRequesting = false
            self.isExecutingTool = false
            self.isCompactingContext = false
            self.fillEmptyAssistantMessage("（模型没有返回文本）")
            self.refreshCacheStatus()
            self.synchronizeSelectedConversation(persist: true)
            self.sendNextQueuedMessageIfPossible()
        }
        agentRuntime.onError = { [weak self] error in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isRequesting = false
            self.isExecutingTool = false
            self.isCompactingContext = false
            self.showToolConfirmation = false
            self.pendingToolSummary = ""
            self.fillEmptyAssistantMessage("请求失败：\(error.localizedDescription)")
            self.refreshCacheStatus()
            self.synchronizeSelectedConversation(persist: true)
            self.sendNextQueuedMessageIfPossible()
        }
    }

    private func sendNextQueuedMessageIfPossible() {
        guard !isBusy, !queuedMessages.isEmpty else { return }
        let next = queuedMessages.removeFirst()
        sendImmediately(next.content, attachments: next.attachments)
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
        conversations[index].agentHistory = agentRuntime.messages
        conversations[index].title = title(for: messages)
        if updateTimestamp {
            conversations[index].updatedAt = .now
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
        let sorted = conversations.sorted(by: { $0.updatedAt > $1.updatedAt })
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: Self.conversationsStorageKey)
        defaults.set(selectedConversationID.uuidString, forKey: Self.selectedConversationStorageKey)
    }

    private static func loadConversations(from defaults: UserDefaults) -> [DialogConversation] {
        guard let data = defaults.data(forKey: conversationsStorageKey),
              let conversations = try? JSONDecoder().decode([DialogConversation].self, from: data) else {
            return []
        }
        return conversations
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
