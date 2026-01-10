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
    @State private var newMessage: String = ""
    @State private var editingIndex: Int? = nil
    @State private var editingText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            // 标签和计数
            HStack {
                Text("静态提示词:")
                    .font(DesignFonts.body)
                
                Spacer()
                
                Text("[\(messages.count) 条]")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            // 消息列表
            if !messages.isEmpty {
                messagesList
            } else {
                emptyState
            }
            
            // 添加新消息
            addMessageField
            
            Text("静态提示词将替代角色的默认自动消息")
                .font(DesignFonts.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 子视图

extension StaticMessagesEditor {
    private var messagesList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    messageRow(index: index, message: message)
                }
            }
        }
        .frame(height: 150)
        .border(DesignColors.border, width: LayoutConstants.borderWidth)
    }
    
    private var emptyState: some View {
        Text("暂无静态提示词，请添加")
            .font(DesignFonts.caption)
            .foregroundColor(.secondary)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.05))
            .border(DesignColors.border, width: LayoutConstants.borderWidth)
    }
    
    private var addMessageField: some View {
        HStack(spacing: 8) {
            TextField("输入新的静态提示词", text: $newMessage)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(DesignFonts.input)
            
            Button(action: addMessage) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    private func messageRow(index: Int, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .font(DesignFonts.input)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
            
            if editingIndex == index {
                TextField("编辑消息", text: $editingText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(DesignFonts.input)
            } else {
                Text(message)
                    .font(DesignFonts.input)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            
            actionButtons(for: index)
        }
        .padding(.vertical, 4)
    }
    
    private func actionButtons(for index: Int) -> some View {
        HStack(spacing: 4) {
            if editingIndex == index {
                Button(action: { saveEdit(at: index) }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: cancelEdit) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: { startEdit(at: index) }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { deleteMessage(at: index) }) {
                    Image(systemName: "trash.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - 操作方法

extension StaticMessagesEditor {
    private func addMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(trimmed)
        newMessage = ""
    }
    
    private func startEdit(at index: Int) {
        editingIndex = index
        editingText = messages[index]
    }
    
    private func saveEdit(at index: Int) {
        messages[index] = editingText
        editingIndex = nil
        editingText = ""
    }
    
    private func cancelEdit() {
        editingIndex = nil
        editingText = ""
    }
    
    private func deleteMessage(at index: Int) {
        messages.remove(at: index)
    }
}
