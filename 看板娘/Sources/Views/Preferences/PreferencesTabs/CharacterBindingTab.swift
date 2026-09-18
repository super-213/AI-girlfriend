//
//  CharacterBindingTab.swift
//  看板娘
//
//  角色库与当前角色绑定。
//

import SwiftUI

private enum CharacterSettingsSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case conversation = "对话"
    case assets = "素材"

    var id: String { rawValue }
}

struct CharacterBindingTab: View {
    let allCharacters: [PetCharacter]
    let customCharacters: [PetCharacter]
    let builtInCharactersCount: Int
    let currentCharacterID: String

    @Binding var selectedCharacterID: String
    @Binding var systemPrompt: String
    @Binding var inputPlaceholder: String
    @Binding var staticMessages: [String]
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding

    let onSaveStyle: () -> Void
    let onCancelStyle: () -> Void
    let styleHasUnsavedChanges: Bool
    let onCharacterChange: (Int) -> Void
    let onImport: (URL?, URL?, String) -> Bool
    let onDelete: (Int) -> Void
    let onConfigure: (Int) -> Void

    @Binding var showImportError: Bool
    @Binding var importErrorMessage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedSection: CharacterSettingsSection = .overview
    @State private var characterPendingDeletion: PetCharacter?
    @State private var isShowingImporter = false
    @State private var selectNewestCharacterAfterImport = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                librarySidebar
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 250)

                Divider()

                detailArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            normalizeSelection(preferCurrentCharacter: true)
        }
        .onChange(of: currentCharacterID) { _, _ in
            normalizeSelection(preferCurrentCharacter: selectedCharacter == nil)
        }
        .onChange(of: customCharacters.map(\.id)) { _, newIDs in
            if selectNewestCharacterAfterImport, let newestID = newIDs.last {
                selectedCharacterID = newestID
                selectNewestCharacterAfterImport = false
            } else {
                normalizeSelection(preferCurrentCharacter: false)
            }
        }
        .sheet(isPresented: $isShowingImporter) {
            CharacterImportSheet(
                onImport: onImport,
                onComplete: { characterName in
                    selectNewestCharacterAfterImport = true
                    statusMessage = "已导入“\(characterName)”，现在可以将它设为当前角色。"
                    isShowingImporter = false
                },
                onCancel: { isShowingImporter = false }
            )
        }
        .confirmationDialog(
            "删除“\(characterPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { characterPendingDeletion != nil },
                set: { if !$0 { characterPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除角色", role: .destructive) {
                deletePendingCharacter()
            }
            Button("取消", role: .cancel) {
                characterPendingDeletion = nil
            }
        } message: {
            Text("角色配置和已复制到应用内的素材会一并移除。此操作无法撤销。")
        }
        .alert("导入失败", isPresented: $showImportError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("角色设置")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.lg) {
            Text("角色")
                .font(.title2.weight(.semibold))

            Spacer()

            Button {
                isShowingImporter = true
            } label: {
                Label("导入角色", systemImage: "plus")
            }
            .disabled(customCharacters.count >= 3)
            .help(customCharacters.count >= 3 ? "最多可保存 3 个自定义角色" : "从 GIF、APNG、PNG 或 JPEG 创建角色")
        }
        .padding(.horizontal, DesignSpacing.xl)
        .padding(.vertical, DesignSpacing.lg)
    }

    private var librarySidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    characterGroup(
                        title: "内置角色",
                        characters: Array(allCharacters.prefix(builtInCharactersCount))
                    )

                    characterGroup(
                        title: "我的角色  \(customCharacters.count)/3",
                        characters: customCharacters,
                        showsEmptyState: true
                    )
                }
                .padding(DesignSpacing.md)
            }
        }
        .background {
            if reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private func characterGroup(
        title: String,
        characters: [PetCharacter],
        showsEmptyState: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, DesignSpacing.sm)

            if characters.isEmpty, showsEmptyState {
                Button {
                    isShowingImporter = true
                } label: {
                    VStack(spacing: DesignSpacing.sm) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 24))
                        Text("导入你的第一个角色")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(characters) { character in
                    CharacterLibraryRow(
                        character: character,
                        isSelected: selectedCharacterID == character.id,
                        isCurrent: currentCharacterID == character.id
                    ) {
                        selectedCharacterID = character.id
                        statusMessage = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailArea: some View {
        if let character = selectedCharacter {
            VStack(spacing: 0) {
                detailHeader(for: character)

                Divider()

                Group {
                    switch selectedSection {
                    case .overview:
                        CharacterDetailPane(
                            character: character,
                            isCustom: customIndex(for: character) != nil,
                            isCurrent: character.id == currentCharacterID,
                            statusMessage: statusMessage,
                            onBind: { bind(character) },
                            onConfigure: nil,
                            onDelete: customIndex(for: character).map { _ in
                                { characterPendingDeletion = character }
                            }
                        )
                    case .conversation:
                        CharacterConversationSettingsPane(
                            characterName: character.name,
                            systemPrompt: $systemPrompt,
                            inputPlaceholder: $inputPlaceholder,
                            staticMessages: $staticMessages,
                            focusedField: focusedField,
                            onSave: onSaveStyle,
                            onCancel: onCancelStyle,
                            hasUnsavedChanges: styleHasUnsavedChanges
                        )
                    case .assets:
                        CharacterAssetsSettingsPane(
                            character: character,
                            isCustom: customIndex(for: character) != nil,
                            onConfigure: customIndex(for: character).map { index in
                                { onConfigure(index) }
                            }
                        )
                    }
                }
                .id("\(character.id)-\(selectedSection.id)")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(
                "没有可用角色",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("导入一个角色后即可开始配置。")
            )
        }
    }

    private func detailHeader(for character: PetCharacter) -> some View {
        HStack(spacing: DesignSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(character.id == currentCharacterID ? "当前角色" : "正在编辑")
                    .font(.caption)
                    .foregroundStyle(character.id == currentCharacterID ? .green : .secondary)
            }

            Spacer()

            Picker("角色设置区域", selection: $selectedSection) {
                ForEach(CharacterSettingsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(.horizontal, DesignSpacing.xl)
        .padding(.vertical, DesignSpacing.md)
    }

    private var selectedCharacter: PetCharacter? {
        return allCharacters.first(where: { $0.id == selectedCharacterID })
    }

    private func customIndex(for character: PetCharacter) -> Int? {
        customCharacters.firstIndex(where: { $0.id == character.id })
    }

    private func bind(_ character: PetCharacter) {
        guard let index = allCharacters.firstIndex(where: { $0.id == character.id }),
              character.id != currentCharacterID else { return }
        onCharacterChange(index)
        statusMessage = "已将“\(character.name)”设为当前角色。"
    }

    private func deletePendingCharacter() {
        guard let character = characterPendingDeletion,
              let index = customIndex(for: character) else {
            characterPendingDeletion = nil
            return
        }

        let wasSelected = selectedCharacterID == character.id
        onDelete(index)
        characterPendingDeletion = nil
        statusMessage = "已删除“\(character.name)”。"

        if wasSelected {
            selectedCharacterID = currentCharacterID == character.id
                ? allCharacters.first?.id ?? ""
                : currentCharacterID
        }
    }

    private func normalizeSelection(preferCurrentCharacter: Bool) {
        if preferCurrentCharacter, allCharacters.contains(where: { $0.id == currentCharacterID }) {
            selectedCharacterID = currentCharacterID
            return
        }

        guard allCharacters.contains(where: { $0.id == selectedCharacterID }) else {
            selectedCharacterID = allCharacters.first(where: { $0.id == currentCharacterID })?.id
                ?? allCharacters.first?.id
                ?? ""
            return
        }
    }
}

private struct CharacterConversationSettingsPane: View {
    let characterName: String
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
                VStack(alignment: .leading, spacing: DesignSpacing.xxl) {
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text("对话风格")
                            .font(.title3.weight(.semibold))
                        Text("这些设置仅对“\(characterName)”生效。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    settingsSection(title: "临时对话框") {
                        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
                            Text("输入框提示语")
                                .font(.subheadline.weight(.semibold))
                            TextField("留空则不显示提示语", text: $inputPlaceholder)
                                .textFieldStyle(.roundedBorder)
                                .font(DesignFonts.input)
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

                    Divider()

                    settingsSection(title: "角色风格") {
                        SystemPromptEditor(
                            text: $systemPrompt,
                            defaultPrompt: PreferencesData.default.systemPrompt,
                            focusedField: focusedField
                        )
                    }

                    Divider()

                    settingsSection(title: "随机主动消息") {
                        StaticMessagesEditor(messages: $staticMessages)
                    }
                }
                .padding(DesignSpacing.xl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            EnhancedActionButtons(
                onSave: onSave,
                onCancel: onCancel,
                isSaveDisabled: !hasUnsavedChanges,
                hasUnsavedChanges: hasUnsavedChanges,
                secondaryTitle: "放弃更改",
                isCancelDisabled: !hasUnsavedChanges
            )
            .padding(.horizontal, DesignSpacing.xl)
            .padding(.vertical, DesignSpacing.md)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.bar)
            )
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

private struct CharacterAssetsSettingsPane: View {
    let character: PetCharacter
    let isCustom: Bool
    let onConfigure: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.xl) {
                CharacterThumbnail(character: character, size: 150, cornerRadius: 20, showsBackground: true)

                VStack(spacing: DesignSpacing.xs) {
                    Text("状态素材")
                        .font(.title3.weight(.semibold))
                    Text(isCustom
                         ? "为站立、工作、思考等状态配置不同素材。"
                         : "内置角色的状态素材由应用提供，不能在此修改。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    assetMetric(value: "\(configuredStateCount)", label: "已配置状态")
                    Divider().frame(height: 34)
                    assetMetric(value: "\(totalAssetCount)", label: "状态素材")
                    Divider().frame(height: 34)
                    assetMetric(value: character.interactionAssets.isEmpty ? "无" : "有", label: "互动素材")
                }
                .padding(.vertical, DesignSpacing.md)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                if let onConfigure {
                    Button(action: onConfigure) {
                        Label("编辑状态素材", systemImage: "photo.on.rectangle.angled")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .padding(DesignSpacing.xxl)
        }
    }

    private func assetMetric(value: String, label: String) -> some View {
        VStack(spacing: DesignSpacing.xs) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var configuredStateCount: Int {
        character.assetsByState.values.filter { !$0.isEmpty }.count
    }

    private var totalAssetCount: Int {
        character.assetsByState.values.reduce(0) { $0 + $1.count }
    }
}
