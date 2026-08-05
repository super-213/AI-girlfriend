//
//  ActionButtons.swift
//  桌面宠物应用
//
//  操作按钮组件
//

import SwiftUI

/// 设置页的标准操作区，使用 macOS 原生按钮层级。
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
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isCancelDisabled)
            
            Button("保存") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isSaveDisabled)
            .keyboardShortcut("s", modifiers: .command)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: hasUnsavedChanges
        )
    }
    
    private var unsavedChangesIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
            Text("未保存的更改")
                .font(DesignFonts.caption)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("有未保存的更改")
    }
}
