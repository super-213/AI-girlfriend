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
    
    var characterCount: Int {
        text.count
    }
    
    var isOverLimit: Bool {
        characterCount > characterLimit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            // 标签和字符计数
            HStack {
                Text("系统提示词:")
                    .font(DesignFonts.body)
                
                Spacer()
                
                Text("[\(characterCount)/\(characterLimit)]")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(isOverLimit ? DesignColors.warning : .secondary)
                    .accessibilityLabel("字符计数：\(characterCount) 个，限制 \(characterLimit) 个")
            }
            
            // 文本编辑器
            TextEditor(text: $text)
                .frame(height: LayoutConstants.systemPromptHeight)
                .border(DesignColors.border, width: LayoutConstants.borderWidth)
                .font(DesignFonts.input)
                .focused(focusedField, equals: .systemPrompt)
                .accessibilityLabel("系统提示词文本编辑器")
                .accessibilityValue(text)
            
            // 超长警告
            if isOverLimit {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("提示词较长，建议精简以获得更好的响应")
                        .font(DesignFonts.caption)
                }
                .foregroundColor(DesignColors.warning)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("警告：提示词较长，建议精简")
            }
            
            // 重置按钮
            Button(action: resetToDefault) {
                Text("重置为默认")
                    .font(.caption)
            }
            .accessibilityLabel("重置系统提示词为默认值")
            .accessibilityHint("将系统提示词恢复为默认设置")
        }
    }
    
    func resetToDefault() {
        text = defaultPrompt
    }
}
