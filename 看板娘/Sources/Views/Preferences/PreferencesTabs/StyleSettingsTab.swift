//
//  StyleSettingsTab.swift
//  桌面宠物应用
//
//  风格设置标签页视图
//

import SwiftUI

/// 风格设置标签页
struct StyleSettingsTab: View {
    let characters: [PetCharacter]
    @Binding var selectedCharacterID: String
    @Binding var systemPrompt: String
    @Binding var inputPlaceholder: String
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
                        title: "绑定桌宠"
                    ) {
                        characterBindingPicker
                    }

                    Divider()

                    settingsSection(
                        title: "临时对话框"
                    ) {
                        inputPlaceholderEditor
                    }

                    Divider()

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
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text("风格")
                .font(.title2.weight(.semibold))
            Text("为每个桌宠设置独立的对话语气与提示文案，切换桌宠时自动生效。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var characterBindingPicker: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Picker("桌宠", selection: $selectedCharacterID) {
                ForEach(characters) { character in
                    Text(character.name).tag(character.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 360, alignment: .leading)
            .accessibilityHint("选择要编辑和绑定风格的桌宠")

            Label("当前页面的全部设置都会绑定到所选桌宠。", systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inputPlaceholderEditor: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            Text("输入框提示语")
                .font(.subheadline.weight(.semibold))

            TextField("留空则不显示提示语", text: $inputPlaceholder)
                .textFieldStyle(.roundedBorder)
                .font(DesignFonts.input)
                .accessibilityLabel("临时对话框输入提示语")

            Text("鼠标移到桌宠上时，临时输入框中显示的灰色文字。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("恢复默认") {
                    inputPlaceholder = PetConversationStyle.defaultInputPlaceholder
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(inputPlaceholder == PetConversationStyle.defaultInputPlaceholder)
            }
        }
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
