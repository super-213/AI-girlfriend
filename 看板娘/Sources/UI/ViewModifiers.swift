//
//  ViewModifiers.swift
//  桌面宠物应用
//
//  用于界面增强的可重用视图修饰器
//  在整个应用中提供一致的样式和交互反馈
//

import SwiftUI

// MARK: - 视图修饰器扩展

extension View {
    /// 应用带有焦点和悬停效果的增强文本字段样式
    func enhancedTextFieldStyle() -> some View {
        self.modifier(EnhancedTextFieldStyle())
    }
    
    /// 应用带有交互反馈的增强按钮样式
    func enhancedButtonStyle(isPrimary: Bool = true, isDisabled: Bool = false) -> some View {
        self.buttonStyle(EnhancedButtonStyle(isPrimary: isPrimary, isDisabled: isDisabled))
    }
    
    /// 应用带有自定义滚动条的平滑滚动样式
    func smoothScrollStyle() -> some View {
        self.modifier(SmoothScrollStyle())
    }
}


// MARK: - 增强文本字段样式

/// 提供贴近 macOS 原生输入框的焦点反馈。
struct EnhancedTextFieldStyle: ViewModifier {
    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isFocused ? DesignColors.borderFocus :
                        DesignColors.border.opacity(isHovered ? 1 : 0.7),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .animation(DesignAnimation.gentle, value: isHovered)
            .animation(DesignAnimation.easeInOut, value: isFocused)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}


// MARK: - 增强按钮样式

/// 保留原生按钮的层级和立即按压反馈，不使用发光或弹跳。
struct EnhancedButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        EnhancedButtonStyleBody(
            configuration: configuration,
            isPrimary: isPrimary,
            isDisabled: isDisabled
        )
    }
}

private struct EnhancedButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(buttonBackgroundColor)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DesignColors.border, lineWidth: 1)
                }
            }
            .foregroundColor(buttonForegroundColor)
            .scaleEffect(configuration.isPressed && !isDisabled ? 0.98 : 1)
            .opacity(isDisabled ? 0.5 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(reduceMotion ? nil : DesignAnimation.gentle, value: isHovered)
            .onHover { hovering in
                if !isDisabled {
                    isHovered = hovering
                }
            }
    }
    
    /// 根据按钮状态计算背景颜色
    private var buttonBackgroundColor: Color {
        if isDisabled {
            return Color(nsColor: .controlColor)
        }
        if isPrimary {
            return configuration.isPressed ? DesignColors.primaryActive :
                   isHovered ? DesignColors.primaryHover :
                   DesignColors.primary
        } else {
            return configuration.isPressed ? Color(nsColor: .selectedControlColor).opacity(0.18) :
                   isHovered ? Color(nsColor: .controlColor).opacity(0.82) :
                   Color(nsColor: .controlColor).opacity(0.55)
        }
    }
    
    /// 根据按钮类型计算前景颜色
    private var buttonForegroundColor: Color {
        isPrimary ? .white : DesignColors.textPrimary
    }
}


// MARK: - 平滑滚动样式

/// 提供平滑滚动行为的视图修饰器
/// 使用系统默认滚动条
struct SmoothScrollStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollIndicators(.automatic)
    }
}
