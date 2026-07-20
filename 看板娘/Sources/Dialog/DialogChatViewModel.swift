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

final class DialogChatViewModel: ObservableObject {
    @Published var messages: [DialogMessage] = []
    @Published var inputText: String = ""
    @Published var isRequesting: Bool = false
    @Published var showCommandConfirm: Bool = false
    @Published var pendingCommand: String = ""
    @Published var isExecutingCommand: Bool = false

    private let apiManager = APIManager()
    private var activeStreamToken = UUID()
    private var lastUserInput: String = ""
    private let maxCommandIterations = 5
    private var commandIterationCount = 0

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRequesting, !isExecutingCommand else { return }

        lastUserInput = trimmed
        commandIterationCount = 0
        messages.append(DialogMessage(role: .user, content: trimmed))
        inputText = ""
        requestAssistantReply()
    }

    func startNewConversation() {
        apiManager.cancelStreamRequest()
        activeStreamToken = UUID()
        isRequesting = false
        isExecutingCommand = false
        showCommandConfirm = false
        pendingCommand = ""
        lastUserInput = ""
        commandIterationCount = 0
        messages.removeAll()
        inputText = ""
    }

    func stopGenerating() {
        guard isRequesting, !isExecutingCommand else { return }
        activeStreamToken = UUID()
        apiManager.cancelStreamRequest()
        isRequesting = false
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
        appendAssistantStatus("已停止生成。")
    }

    func confirmAndRunCommand() {
        let command = pendingCommand
        showCommandConfirm = false
        pendingCommand = ""

        guard !command.isEmpty else { return }

        guard CommandExecutionSupport.isCommandSafe(command) else {
            appendAssistantStatus("[完成] 已阻止危险或交互式命令: \(command)")
            return
        }

        isExecutingCommand = true
        isRequesting = true

        DispatchQueue.global(qos: .userInitiated).async {
            let (exitCode, output) = CommandExecutionSupport.runShell(command)
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.isExecutingCommand = false
                self.commandIterationCount += 1

                guard self.commandIterationCount <= self.maxCommandIterations else {
                    self.isRequesting = false
                    self.appendAssistantStatus("[完成] 命令执行次数过多，已停止自动执行")
                    return
                }

                let resultText = """
                执行完毕
                命令: \(command)
                退出码: \(exitCode)
                输出:
                \(trimmedOutput.isEmpty ? "(无输出)" : trimmedOutput)
                """
                self.messages.append(DialogMessage(role: .user, content: resultText))
                self.requestAssistantReply()
            }
        }
    }

    func cancelPendingCommand() {
        showCommandConfirm = false
        pendingCommand = ""
        isRequesting = false
        appendAssistantStatus("[完成] 已取消执行命令")
    }

    private func requestAssistantReply() {
        let outgoingMessages = buildOutgoingMessages()
        let assistantID = UUID()
        let streamToken = UUID()

        activeStreamToken = streamToken
        isRequesting = true
        messages.append(DialogMessage(id: assistantID, role: .assistant, content: ""))

        apiManager.sendStreamRequest(messages: outgoingMessages) { [weak self] newContent in
            Task { @MainActor [weak self] in
                self?.appendAssistantChunk(newContent, to: assistantID, streamToken: streamToken)
            }
        } onComplete: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishAssistantReply(for: assistantID, streamToken: streamToken)
            }
        } onError: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.activeStreamToken == streamToken else { return }
                self.isRequesting = false
                self.appendAssistantStatus("请求失败：\(error.localizedDescription)")
            }
        }
    }

    private func appendAssistantChunk(_ chunk: String, to messageID: UUID, streamToken: UUID) {
        guard activeStreamToken == streamToken else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].content += chunk
    }

    private func finishAssistantReply(for messageID: UUID, streamToken: UUID) {
        guard activeStreamToken == streamToken else { return }
        isRequesting = false

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let content = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            messages[index].content = "（未收到模型回复）"
            return
        }

        handleAssistantReply(messageID: messageID, assistantReply: content)
    }

    private func handleAssistantReply(messageID: UUID, assistantReply: String) {
        guard !CommandExecutionSupport.isCompletionReply(assistantReply) else { return }
        guard !isExecutingCommand else { return }
        guard let command = CommandExecutionSupport.extractCommand(from: assistantReply) else { return }

        let normalized = CommandExecutionSupport.normalizeCommand(command, basedOn: lastUserInput)
        pendingCommand = normalized

        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        if normalized != command, let range = messages[index].content.range(of: command) {
            messages[index].content.replaceSubrange(range, with: normalized)
        }

        if !CommandExecutionSupport.hasCommandTag(in: messages[index].content) {
            messages[index].content += "\n[命令] \(normalized)"
        }

        showCommandConfirm = true
    }

    private func appendAssistantStatus(_ status: String) {
        messages.append(DialogMessage(role: .assistant, content: status))
    }

    private func buildOutgoingMessages() -> [[String: String]] {
        var outgoing: [[String: String]] = [
            ["role": "system", "content": apiManager.systemPromptContent()]
        ]

        for item in messages {
            outgoing.append([
                "role": item.role.rawValue,
                "content": item.content
            ])
        }
        return outgoing
    }
}
