//
//  ActionButtons.swift
//  桌面宠物应用
//
//  操作按钮组件
//

import SwiftUI

/// 增强的操作按钮组组件
/// 提供保存和取消按钮，包含未保存更改的脉动指示器
struct EnhancedActionButtons: View {
    let onSave: () -> Void
    let onCancel: () -> Void
    let isSaveDisabled: Bool
    let hasUnsavedChanges: Bool
    var secondaryTitle: String = "取消"
    var isCancelDisabled: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            if hasUnsavedChanges {
                unsavedChangesIndicator
            }
            
            Spacer()
            
            Button(secondaryTitle) {
                onCancel()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: false, isDisabled: isCancelDisabled)
            .disabled(isCancelDisabled)
            
            Button("保存") {
                onSave()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: true, isDisabled: isSaveDisabled)
            .disabled(isSaveDisabled)
            .keyboardShortcut("s", modifiers: .command)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
            value: hasUnsavedChanges
        )
    }
    
    private var unsavedChangesIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DesignColors.warning)
                .frame(width: 8, height: 8)
            Text("未保存的更改")
                .font(DesignFonts.caption)
                .foregroundColor(.secondary)
        }
        .transition(.opacity.combined(with: .scale))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("有未保存的更改")
    }
}
