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
    
    @State private var pulseAnimation: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            if hasUnsavedChanges {
                unsavedChangesIndicator
            }
            
            Spacer()
            
            Button("取消") {
                onCancel()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: false, isDisabled: false)
            
            Button("保存") {
                onSave()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: true, isDisabled: isSaveDisabled)
            .disabled(isSaveDisabled)
        }
    }
    
    private var unsavedChangesIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DesignColors.warning)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseAnimation)
                .animation(
                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulseAnimation
                )
            Text("未保存的更改")
                .font(DesignFonts.caption)
                .foregroundColor(.secondary)
        }
        .transition(.opacity.combined(with: .scale))
        .onAppear {
            pulseAnimation = 1.3
        }
        .onDisappear {
            pulseAnimation = 1.0
        }
    }
}
