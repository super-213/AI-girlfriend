//
//  StaticMessagesEditor.swift
//  桌面宠物应用
//
//  静态提示词列表编辑器组件
//

import SwiftUI

/// 静态提示词列表编辑器组件
/// 支持添加、编辑和删除静态提示词
struct StaticMessagesEditor: View {
    @Binding var messages: [String]
    @State private var newMessage = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @FocusState private var focusedInput: FocusedInput?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum FocusedInput: Hashable {
        case newMessage
        case message(Int)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("自动消息")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Text("\(messages.count) 条")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            // 消息列表
            if !messages.isEmpty {
                messagesList
            } else {
                emptyState
            }
            
            addMessageField
            
            Text("角色会从这些消息中随机选取一条；留空则使用角色默认消息。")
                .font(DesignFonts.caption)
                .foregroundColor(.secondary)
        }
        .onExitCommand(perform: cancelEdit)
        .onChange(of: messages) { _, _ in
            // “还原”或其他外部更新发生时，不保留已过期的行编辑状态。
            if editingIndex != nil {
                cancelEdit()
            }
        }
    }
}

// MARK: - 子视图

extension StaticMessagesEditor {
    private var messagesList: some View {
        VStack(spacing: DesignSpacing.xs) {
            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                messageRow(index: index, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
    
    private var emptyState: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "text.bubble")
            Text("还没有自动消息")
        }
        .font(DesignFonts.caption)
        .foregroundStyle(.secondary)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private var addMessageField: some View {
        HStack(spacing: 8) {
            TextField("输入新的自动消息", text: $newMessage)
                .textFieldStyle(.roundedBorder)
                .font(DesignFonts.input)
                .focused($focusedInput, equals: .newMessage)
                .onSubmit(addMessage)
            
            Button(action: addMessage) {
                Label("添加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("添加消息（回车）")
        }
    }
    
    private func messageRow(index: Int, message: String) -> some View {
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            
            if editingIndex == index {
                TextField("编辑消息", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignFonts.input)
                    .focused($focusedInput, equals: .message(index))
                    .onSubmit { saveEdit(at: index) }
            } else {
                Text(message)
                    .font(DesignFonts.input)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            
            actionButtons(for: index)
        }
        .padding(.horizontal, DesignSpacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    editingIndex == index
                        ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    editingIndex == index ? DesignColors.borderFocus.opacity(0.7) : DesignColors.border,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard editingIndex != index else { return }
            startEdit(at: index)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(index + 1) 条自动消息")
    }
    
    private func actionButtons(for index: Int) -> some View {
        HStack(spacing: 4) {
            if editingIndex == index {
                Button(action: { saveEdit(at: index) }) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("完成编辑（回车）")
                
                Button(action: cancelEdit) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("取消编辑（Esc）")
            } else {
                Button(action: { startEdit(at: index) }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("编辑消息")
                
                Button(action: { deleteMessage(at: index) }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .help("删除消息（可通过“还原”恢复）")
            }
        }
    }
}

// MARK: - 操作方法

extension StaticMessagesEditor {
    private func addMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
            messages.append(trimmed)
        }
        newMessage = ""
        focusedInput = .newMessage
    }
    
    private func startEdit(at index: Int) {
        guard messages.indices.contains(index) else { return }
        editingIndex = index
        editingText = messages[index]
        focusedInput = .message(index)
    }
    
    private func saveEdit(at index: Int) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard messages.indices.contains(index), !trimmed.isEmpty else { return }
        messages[index] = trimmed
        editingIndex = nil
        editingText = ""
        focusedInput = nil
    }
    
    private func cancelEdit() {
        editingIndex = nil
        editingText = ""
        focusedInput = nil
    }
    
    private func deleteMessage(at index: Int) {
        guard messages.indices.contains(index) else { return }
        _ = withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
            messages.remove(at: index)
        }

        if editingIndex == index {
            cancelEdit()
        } else if let editingIndex, editingIndex > index {
            self.editingIndex = editingIndex - 1
        }
    }
}
