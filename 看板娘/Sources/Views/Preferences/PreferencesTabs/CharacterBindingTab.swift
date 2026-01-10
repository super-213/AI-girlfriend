//
//  CharacterBindingTab.swift
//  桌面宠物应用
//
//  角色绑定标签页视图
//

import SwiftUI

/// 角色绑定标签页
struct CharacterBindingTab: View {
    @Binding var selectedIndex: Int
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    let allCharacters: [PetCharacter]
    let customCharacters: [PetCharacter]
    let availableCharactersCount: Int
    
    let onCharacterChange: (Int) -> Void
    let onImport: () -> Void
    let onDelete: (Int) -> Void
    
    @Binding var showImportError: Bool
    @Binding var importErrorMessage: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                Text("角色绑定管理")
                    .font(DesignFonts.title)
                    .padding(.top, DesignSpacing.md)
                
                // 角色选择器
                CharacterPickerSection(
                    selectedIndex: $selectedIndex,
                    allCharacters: allCharacters,
                    customCharactersCount: customCharacters.count,
                    focusedField: focusedField,
                    onCharacterChange: onCharacterChange
                )
                .padding(.horizontal, DesignSpacing.xl)
                
                Divider()
                    .padding(.vertical, DesignSpacing.md)
                
                // 自定义角色管理
                CustomCharactersSection(
                    customCharacters: customCharacters,
                    onImport: onImport,
                    onDelete: onDelete
                )
                .padding(.horizontal, DesignSpacing.xl)
                
                Spacer()
            }
        }
        .alert("导入失败", isPresented: $showImportError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("角色绑定标签")
    }
}
