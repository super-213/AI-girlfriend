//
//  DialogChatView.swift
//  看板娘
//
//  对话窗口视图与 NSSearchField 封装
//

import AppKit
import SwiftUI

struct DialogChatView: View {
    @ObservedObject var viewModel: DialogChatViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()
                .background(Color.white.opacity(0.14))

            messageArea

            Divider()
                .background(Color.white.opacity(0.14))

            inputArea
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        )
    }

    private var toolbar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 14, height: 14)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.9))
                    )
            }
            .buttonStyle(.plain)
            .help("关闭")

            Spacer()

            Button("新建对话") {
                viewModel.startNewConversation()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("开始一段新对话")
                            .font(.system(size: 17, weight: .semibold))
                        Text("历史会自动带入下一轮请求。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            messageBubble(for: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputArea: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                DialogSearchField(
                    text: $viewModel.inputText,
                    placeholder: "输入消息后回车发送",
                    onSubmit: {
                        viewModel.sendCurrentInput()
                    }
                )
                .frame(height: 34)
                .disabled(viewModel.isRequesting)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )

            if viewModel.isRequesting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func messageBubble(for message: DialogMessage) -> some View {
        let isUser = message.role == .user
        let bubbleColor = Color.gray.opacity(0.16)

        return HStack {
            if isUser {
                Spacer(minLength: 50)
            }

            Text(message.content)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bubbleColor)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 50)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

struct DialogSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.controlSize = .large
        field.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        field.maximumRecents = 0
        field.recentsAutosaveName = nil
        if let cell = field.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let parent: DialogSearchField

        init(_ parent: DialogSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
