//
//  CharacterBindingTab.swift
//  看板娘
//
//  角色库与当前角色绑定。
//

import SwiftUI

struct CharacterBindingTab: View {
    let allCharacters: [PetCharacter]
    let customCharacters: [PetCharacter]
    let builtInCharactersCount: Int
    let currentCharacterID: String

    let onCharacterChange: (Int) -> Void
    let onImport: (URL?, URL?, String) -> Bool
    let onDelete: (Int) -> Void
    let onConfigure: (Int) -> Void

    @Binding var showImportError: Bool
    @Binding var importErrorMessage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedCharacterID: String?
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
            normalizeSelection(preferCurrentCharacter: selectedCharacterID == nil)
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
        .accessibilityLabel("角色绑定")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text("角色绑定")
                    .font(.title2.weight(.semibold))
                Text("浏览角色库，并选择显示在桌面上的角色。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingImporter = true
            } label: {
                Label("导入角色", systemImage: "plus")
            }
            .disabled(customCharacters.count >= 3)
            .help(customCharacters.count >= 3 ? "最多可保存 3 个自定义角色" : "从 GIF、PNG 或 JPEG 创建角色")
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

            Divider()

            Label("共 \(allCharacters.count) 个可用角色", systemImage: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.vertical, DesignSpacing.md)
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
            CharacterDetailPane(
                character: character,
                isCustom: customIndex(for: character) != nil,
                isCurrent: character.id == currentCharacterID,
                statusMessage: statusMessage,
                onBind: { bind(character) },
                onConfigure: customIndex(for: character).map { index in
                    { onConfigure(index) }
                },
                onDelete: customIndex(for: character).map { _ in
                    { characterPendingDeletion = character }
                }
            )
            .id(character.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
        } else {
            ContentUnavailableView(
                "没有可用角色",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("导入一个角色后即可进行绑定。")
            )
        }
    }

    private var selectedCharacter: PetCharacter? {
        guard let selectedCharacterID else { return nil }
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
                ? allCharacters.first?.id
                : currentCharacterID
        }
    }

    private func normalizeSelection(preferCurrentCharacter: Bool) {
        if preferCurrentCharacter, allCharacters.contains(where: { $0.id == currentCharacterID }) {
            selectedCharacterID = currentCharacterID
            return
        }

        guard let selectedCharacterID,
              allCharacters.contains(where: { $0.id == selectedCharacterID }) else {
            self.selectedCharacterID = allCharacters.first(where: { $0.id == currentCharacterID })?.id
                ?? allCharacters.first?.id
            return
        }
    }
}
