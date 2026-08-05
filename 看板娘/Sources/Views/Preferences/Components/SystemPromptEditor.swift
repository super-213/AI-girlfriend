//
//  SystemPromptEditor.swift
//  桌面宠物应用
//
//  系统提示词编辑器组件
//

import SwiftUI

/// 系统提示词编辑器组件
/// 支持多行编辑、字符计数和重置功能
struct SystemPromptEditor: View {
    @Binding var text: String
    let characterLimit: Int = 500
    let defaultPrompt: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let editorCornerRadius: CGFloat = 8
    
    var characterCount: Int {
        text.count
    }
    
    var isOverLimit: Bool {
        characterCount > characterLimit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("角色指令")
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Text("\(characterCount) / \(characterLimit)")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(isOverLimit ? DesignColors.warning : .secondary)
                    .accessibilityLabel("字符计数：\(characterCount) 个，限制 \(characterLimit) 个")
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("描述角色的身份、语气和回答方式…")
                        .font(DesignFonts.input)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .padding(DesignSpacing.sm)
                    .scrollContentBackground(.hidden)
                    .focused(focusedField, equals: .systemPrompt)
                    .accessibilityLabel("角色指令文本编辑器")
                    .accessibilityValue(text)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, idealHeight: 220, maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: editorCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: editorCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: editorCornerRadius, style: .continuous)
                    .stroke(
                        focusedField.wrappedValue == .systemPrompt
                            ? DesignColors.borderFocus
                            : DesignColors.border,
                        lineWidth: focusedField.wrappedValue == .systemPrompt ? 1.5 : 1
                    )
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: focusedField.wrappedValue == .systemPrompt
            )
            
            // 超长警告
            if isOverLimit {
                Label("提示词较长，建议精简以获得更好的响应", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.warning)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("警告：提示词较长，建议精简")
            }
            
            HStack {
                Spacer()

                Button("恢复默认", action: resetToDefault)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(text == defaultPrompt)
            }
            .accessibilityLabel("重置系统提示词为默认值")
            .accessibilityHint("将系统提示词恢复为默认设置")
        }
    }
    
    func resetToDefault() {
        text = defaultPrompt
        focusedField.wrappedValue = .systemPrompt
    }
}
