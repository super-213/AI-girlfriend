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

    private let apiManager = APIManager()
    private var activeStreamToken = UUID()

    func sendCurrentInput() {
        send(inputText)
    }

    func send(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRequesting else { return }

        messages.append(DialogMessage(role: .user, content: trimmed))
        inputText = ""
        requestAssistantReply()
    }

    func startNewConversation() {
        activeStreamToken = UUID()
        isRequesting = false
        messages.removeAll()
        inputText = ""
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
        }
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
