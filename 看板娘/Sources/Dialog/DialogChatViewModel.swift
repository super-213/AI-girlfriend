//
//  DialogChatViewModel.swift
//  看板娘
//
//  对话窗口的状态管理与上下文聊天请求
//

import Foundation
import SwiftUI

struct DialogMessage: Identifiable, Equatable {
    enum Role: String {
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

@MainActor
final class DialogChatViewModel: ObservableObject {
    @Published var messages: [DialogMessage] = []
    @Published var inputText: String = ""
    @Published var isRequesting: Bool = false
    @Published var showToolConfirmation: Bool = false
    @Published var pendingToolSummary: String = ""
    @Published var isExecutingTool: Bool = false

    private let apiManager = APIManager()
    private lazy var agentRuntime = AgentRuntime(apiManager: apiManager) { [apiManager] in
        apiManager.systemPromptContent()
    }
    private var activeAssistantID: UUID?

    init() {
        configureAgentRuntime()
    }

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRequesting, !isExecutingTool else { return }

        messages.append(DialogMessage(role: .user, content: trimmed))
        inputText = ""
        agentRuntime.send(trimmed)
    }

    func startNewConversation() {
        agentRuntime.startNewConversation()
        isRequesting = false
        isExecutingTool = false
        showToolConfirmation = false
        pendingToolSummary = ""
        activeAssistantID = nil
        messages.removeAll()
        inputText = ""
    }

    func stopGenerating() {
        guard isRequesting, !isExecutingTool else { return }
        agentRuntime.cancel()
        isRequesting = false
        isExecutingTool = false
        showToolConfirmation = false
        pendingToolSummary = ""
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
        appendAssistantStatus("已停止生成。")
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
            let id = UUID()
            self.activeAssistantID = id
            self.isRequesting = true
            self.isExecutingTool = false
            self.messages.append(DialogMessage(id: id, role: .assistant, content: ""))
        }
        agentRuntime.onAssistantText = { [weak self] chunk in
            guard let self, let id = self.activeAssistantID else { return }
            self.appendAssistantChunk(chunk, to: id)
        }
        agentRuntime.onToolStarted = { [weak self] name in
            guard let self else { return }
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
            self.isExecutingTool = false
            self.pendingToolSummary = approval.summary
            self.fillEmptyAssistantMessage("请求调用工具：\(approval.toolName)")
            self.showToolConfirmation = true
        }
        agentRuntime.onCompleted = { [weak self] in
            guard let self else { return }
            self.isRequesting = false
            self.isExecutingTool = false
            self.fillEmptyAssistantMessage("（模型没有返回文本）")
        }
        agentRuntime.onError = { [weak self] error in
            guard let self else { return }
            self.isRequesting = false
            self.isExecutingTool = false
            self.showToolConfirmation = false
            self.pendingToolSummary = ""
            self.fillEmptyAssistantMessage("请求失败：\(error.localizedDescription)")
        }
    }

    private func appendAssistantStatus(_ status: String) {
        messages.append(DialogMessage(role: .assistant, content: status))
    }

}
