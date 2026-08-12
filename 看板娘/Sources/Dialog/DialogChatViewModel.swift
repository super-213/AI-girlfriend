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

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
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

@MainActor
final class DialogChatViewModel: ObservableObject {
    @Published private(set) var conversations: [DialogConversation]
    @Published private(set) var selectedConversationID: UUID
    @Published var messages: [DialogMessage]
    @Published var inputText: String = ""
    @Published var isRequesting: Bool = false
    @Published var showToolConfirmation: Bool = false
    @Published var pendingToolSummary: String = ""
    @Published var isExecutingTool: Bool = false

    private static let conversationsStorageKey = "dialog.conversations.v1"
    private static let selectedConversationStorageKey = "dialog.selectedConversation.v1"

    private let defaults: UserDefaults
    private let apiManager = APIManager()
    private lazy var agentRuntime = AgentRuntime(apiManager: apiManager) { [weak self, apiManager] in
        let style = PetConversationStyleStore.activeStyle(defaults: self?.defaults ?? .standard)
        return apiManager.systemPromptContent(basePrompt: style.systemPrompt)
    }
    private var activeAssistantID: UUID?
    private lazy var streamTextCoalescer = StreamingTextCoalescer { [weak self] text in
        guard let self, let id = self.activeAssistantID else { return }
        self.appendAssistantChunk(text, to: id)
    }

    var selectedConversationTitle: String {
        conversations.first(where: { $0.id == selectedConversationID })?.title ?? "对话"
    }

    var isBusy: Bool {
        isRequesting || isExecutingTool
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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

        configureAgentRuntime()
        agentRuntime.restoreConversation(initialConversation.agentHistory)
    }

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        messages.append(DialogMessage(role: .user, content: trimmed))
        inputText = ""
        agentRuntime.send(trimmed)
        synchronizeSelectedConversation(persist: true)
    }

    func startNewConversation() {
        guard !isBusy else { return }

        synchronizeSelectedConversation(persist: true, updateTimestamp: false)
        if messages.isEmpty {
            inputText = ""
            return
        }

        streamTextCoalescer.reset()
        let conversation = DialogConversation()
        conversations.append(conversation)
        selectedConversationID = conversation.id
        messages = []
        inputText = ""
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
        showToolConfirmation = false
        pendingToolSummary = ""
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
        appendAssistantStatus("已停止生成。")
        synchronizeSelectedConversation(persist: true)
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
        agentRuntime.onAssistantResponseStarted = { [weak self] in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            let id = UUID()
            self.activeAssistantID = id
            self.isRequesting = true
            self.isExecutingTool = false
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
            self.fillEmptyAssistantMessage("（模型没有返回文本）")
            self.synchronizeSelectedConversation(persist: true)
        }
        agentRuntime.onError = { [weak self] error in
            guard let self else { return }
            self.streamTextCoalescer.flush()
            self.isRequesting = false
            self.isExecutingTool = false
            self.showToolConfirmation = false
            self.pendingToolSummary = ""
            self.fillEmptyAssistantMessage("请求失败：\(error.localizedDescription)")
            self.synchronizeSelectedConversation(persist: true)
        }
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
}
