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
                        title: "角色风格",
                        subtitle: "定义角色如何理解自己、组织回答以及与你交流。"
                    ) {
                        SystemPromptEditor(
                            text: $systemPrompt,
                            defaultPrompt: PreferencesData.default.systemPrompt,
                            focusedField: focusedField
                        )
                    }

                    Divider()

                    settingsSection(
                        title: "主动互动",
                        subtitle: "管理角色在没有对话时可以主动说的话。"
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
        VStack(alignment: .leading, spacing: 5) {
            Text("风格")
                .font(.title2.weight(.semibold))
            Text("调整角色的语气、行为与主动消息。更改会在保存后生效。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
    }
}
