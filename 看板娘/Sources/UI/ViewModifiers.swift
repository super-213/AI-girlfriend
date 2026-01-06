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
        self.modifier(EnhancedButtonStyle(isPrimary: isPrimary, isDisabled: isDisabled))
    }
    
    /// 应用带有自定义滚动条的平滑滚动样式
    func smoothScrollStyle() -> some View {
        self.modifier(SmoothScrollStyle())
    }
}


// MARK: - 增强文本字段样式

/// 通过焦点和悬停效果增强文本字段的视图修饰器
/// 通过发光边框、缩放和平滑过渡提供视觉反馈
struct EnhancedTextFieldStyle: ViewModifier {
    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(DesignSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignColors.surfaceLight)
                    .shadow(
                        color: isFocused ? DesignColors.borderFocus : .clear,
                        radius: isFocused ? 4 : 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isFocused ? DesignColors.borderFocus :
                        isHovered ? DesignColors.border : .clear,
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(DesignAnimation.gentle, value: isHovered)
            .animation(DesignAnimation.easeInOut, value: isFocused)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}


// MARK: - 增强按钮样式

/// 通过交互反馈增强按钮的视图修饰器
/// 支持主要和次要按钮样式，包含悬停、按下和禁用状态
struct EnhancedButtonStyle: ViewModifier {
    let isPrimary: Bool
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    let isDisabled: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonBackgroundColor)
            )
            .foregroundColor(buttonForegroundColor)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
            .opacity(isDisabled ? 0.5 : 1.0)
            .animation(DesignAnimation.gentle, value: isHovered)
            .animation(DesignAnimation.fast, value: isPressed)
            .onHover { hovering in
                if !isDisabled {
                    isHovered = hovering
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isDisabled {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
    
    /// 根据按钮状态计算背景颜色
    private var buttonBackgroundColor: Color {
        if isDisabled {
            return DesignColors.secondary.opacity(0.3)
        }
        if isPrimary {
            return isPressed ? DesignColors.primaryActive :
                   isHovered ? DesignColors.primaryHover :
                   DesignColors.primary
        } else {
            return isPressed ? DesignColors.secondary.opacity(0.4) :
                   isHovered ? DesignColors.secondary.opacity(0.3) :
                   DesignColors.secondary.opacity(0.2)
        }
    }
    
    /// 根据按钮类型计算前景颜色
    private var buttonForegroundColor: Color {
        isPrimary ? .white : DesignColors.textPrimary
    }
}


// MARK: - 平滑滚动样式

/// 提供带有自定义滚动条样式的平滑滚动的视图修饰器
/// 隐藏默认滚动条并显示细圆角的自定义滚动条
struct SmoothScrollStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .overlay(
                // 自定义滚动条覆盖层
                GeometryReader { geometry in
                    Rectangle()
                        .fill(DesignColors.border)
                        .frame(width: 4)
                        .cornerRadius(2)
                        .padding(.trailing, 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            )
    }
}
