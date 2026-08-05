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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    pageHeader

                    settingsSection(
                        title: "角色风格"
                    ) {
                        SystemPromptEditor(
                            text: $systemPrompt,
                            defaultPrompt: PreferencesData.default.systemPrompt,
                            focusedField: focusedField
                        )
                    }

                    Divider()

                    settingsSection(
                        title: "随机主动消息"
                    ) {
                        StaticMessagesEditor(messages: $staticMessages)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            EnhancedActionButtons(
                onSave: onSave,
                onCancel: onCancel,
                isSaveDisabled: !hasUnsavedChanges,
                hasUnsavedChanges: hasUnsavedChanges,
                secondaryTitle: "还原",
                isCancelDisabled: !hasUnsavedChanges
            )
            .padding(.horizontal, DesignSpacing.xl)
            .padding(.vertical, DesignSpacing.md)
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("风格设置")
    }

    private var pageHeader: some View {
        Text("风格")
            .font(.title2.weight(.semibold))
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Text(title)
                .font(.headline)

            content()
        }
    }
}
