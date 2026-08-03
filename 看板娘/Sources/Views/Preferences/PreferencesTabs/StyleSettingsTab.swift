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
                VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                    pageHeader

                    settingsSection(
                        icon: "person.text.rectangle",
                        title: "角色风格",
                        subtitle: "定义角色如何理解自己、组织回答以及与你交流。"
                    ) {
                        SystemPromptEditor(
                            text: $systemPrompt,
                            defaultPrompt: PreferencesData.default.systemPrompt,
                            focusedField: focusedField
                        )
                    }

                    settingsSection(
                        icon: "bubble.left.and.bubble.right",
                        title: "主动互动",
                        subtitle: "管理角色在没有对话时可以主动说的话。"
                    ) {
                        StaticMessagesEditor(messages: $staticMessages)
                    }
                }
                .padding(DesignSpacing.xl)
                .frame(maxWidth: 720, alignment: .leading)
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
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text("风格")
                .font(.title2.weight(.semibold))
            Text("调整角色的语气、行为与主动消息。更改会在保存后生效。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentColor.opacity(0.11)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(DesignSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
