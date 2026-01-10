//
//  CharacterComponents.swift
//  桌面宠物应用
//
//  角色绑定相关的UI组件
//

import SwiftUI

/// 角色选择器部分
struct CharacterPickerSection: View {
    @Binding var selectedIndex: Int
    let allCharacters: [PetCharacter]
    let customCharactersCount: Int
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    let onCharacterChange: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("当前角色：")
                .font(DesignFonts.headline)
                .foregroundColor(DesignColors.textPrimary)
            
            Picker("选择角色", selection: $selectedIndex) {
                ForEach(0..<allCharacters.count, id: \.self) { index in
                    Text(allCharacters[index].name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .focused(focusedField, equals: .characterPicker)
            .accessibilityLabel("角色选择器")
            .accessibilityHint("选择不同的桌面宠物角色")
            .onChange(of: selectedIndex) { _, newValue in
                onCharacterChange(newValue)
            }
            
            // 角色数量显示
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(DesignFonts.caption)
                Text("可用角色: \(allCharacters.count) 个 (内置: \(allCharacters.count - customCharactersCount), 自定义: \(customCharactersCount))")
                    .font(DesignFonts.caption)
            }
            .foregroundColor(DesignColors.textSecondary)
        }
    }
}

/// 自定义角色管理部分
struct CustomCharactersSection: View {
    let customCharacters: [PetCharacter]
    let onImport: () -> Void
    let onDelete: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack {
                Text("自定义角色 (\(customCharacters.count)/3)")
                    .font(DesignFonts.headline)
                Spacer()
                Button(action: onImport) {
                    Label("导入", systemImage: "plus.circle.fill")
                }
                .disabled(customCharacters.count >= 3)
            }
            
            if customCharacters.isEmpty {
                Text("暂无自定义角色，点击导入按钮添加")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignSpacing.lg)
            } else {
                ForEach(Array(customCharacters.enumerated()), id: \.offset) { index, character in
                    CustomCharacterRow(
                        character: character,
                        onDelete: { onDelete(index) }
                    )
                }
            }
        }
    }
}

/// 自定义角色行视图
struct CustomCharacterRow: View {
    let character: PetCharacter
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(DesignFonts.body)
                Text("站立: \(URL(fileURLWithPath: character.normalGif).lastPathComponent)")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                Text("动作: \(URL(fileURLWithPath: character.clickGif).lastPathComponent)")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
