//
//  StyleSettingsTab.swift
//  桌面宠物应用
//
//  风格设置标签页视图
//

import SwiftUI

/// 风格设置标签页
struct StyleSettingsTab: View {
    @Binding var systemPrompt: String
    @Binding var staticMessages: [String]
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    let onSave: () -> Void
    let onCancel: () -> Void
    let hasUnsavedChanges: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                SystemPromptEditor(
                    text: $systemPrompt,
                    defaultPrompt: PreferencesData.default.systemPrompt,
                    focusedField: focusedField
                )
                .accessibilityLabel("系统提示词编辑器")
                .accessibilityHint("编辑 AI 角色的个性和行为设置")
                
                Divider()
                    .padding(.vertical, LayoutConstants.fieldSpacing)
                
                StaticMessagesEditor(messages: $staticMessages)
                    .accessibilityLabel("静态提示词编辑器")
                    .accessibilityHint("管理自动回复的静态提示词列表")

                Spacer()

                EnhancedActionButtons(
                    onSave: onSave,
                    onCancel: onCancel,
                    isSaveDisabled: false,
                    hasUnsavedChanges: hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("风格设置标签")
    }
}
