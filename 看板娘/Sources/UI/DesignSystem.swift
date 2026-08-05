//
//  DesignSystem.swift
//  桌面宠物应用
//
//  界面增强的设计令牌和样式系统
//

import SwiftUI

// MARK: - 设计颜色

/// 以 macOS 动态系统颜色为基础的语义色。
/// 跟随用户的强调色、深浅色外观与对比度设置，避免在设置界面中引入额外的“品牌色”。
struct DesignColors {
    // MARK: 主要颜色
    
    /// 用户在系统设置中选择的强调色
    static let primary = Color(nsColor: .controlAccentColor)
    
    /// 悬停状态的主要颜色
    static let primaryHover = primary.opacity(0.88)
    
    /// 激活/按下状态的主要颜色
    static let primaryActive = primary.opacity(0.72)
    
    // MARK: 次要颜色
    
    /// 次要内容颜色
    static let secondary = Color(nsColor: .secondaryLabelColor)
    
    /// 只保留一套强调色，避免多种饱和色同时竞争注意力
    static let accent = primary
    
    // MARK: 语义颜色
    
    /// 成功状态颜色
    static let success = Color(nsColor: .systemGreen)
    
    /// 警告状态颜色
    static let warning = Color(nsColor: .systemOrange)
    
    /// 错误状态颜色
    static let error = Color(nsColor: .systemRed)
    
    /// 信息状态颜色
    static let info = Color(nsColor: .systemBlue)
    
    // MARK: 背景和表面颜色
    
    /// 浅色表面背景
    static let surfaceLight = Color(nsColor: .controlBackgroundColor)
    
    /// 中等表面背景
    static let surfaceMedium = Color(nsColor: .windowBackgroundColor)
    
    /// 深色表面背景
    static let surfaceHeavy = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    
    // MARK: 文本颜色
    
    /// 主要文本颜色
    static let textPrimary = Color(nsColor: .labelColor)
    
    /// 次要文本颜色
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    
    /// 表面背景上的文本颜色
    static let textOnSurface = Color.white
    
    // MARK: 边框和分隔线颜色
    
    /// 默认边框颜色
    static let border = Color(nsColor: .separatorColor)
    
    /// 焦点状态的边框颜色
    static let borderFocus = Color(nsColor: .keyboardFocusIndicatorColor)
    
    /// 错误状态的边框颜色
    static let borderError = Color(nsColor: .systemRed)
}

// MARK: - 设计间距

/// 统一的间距系统，用于一致的布局
/// 提供从超小到超大的标准化间距值
struct DesignSpacing {
    /// 超小间距 (4pt)
    static let xs: CGFloat = 4
    
    /// 小间距 (8pt)
    static let sm: CGFloat = 8
    
    /// 中等间距 (12pt)
    static let md: CGFloat = 12
    
    /// 大间距 (16pt)
    static let lg: CGFloat = 16
    
    /// 超大间距 (20pt)
    static let xl: CGFloat = 20
    
    /// 特大间距 (24pt)
    static let xxl: CGFloat = 24
}

// MARK: - 设计动画

/// 一致动作设计的动画配置
/// 定义标准持续时间和缓动函数
struct DesignAnimation {
    // MARK: 动画持续时间
    
    /// 快速动画持续时间 (150ms)
    static let fastDuration: Double = 0.15
    
    /// 正常动画持续时间 (250ms)
    static let normalDuration: Double = 0.25
    
    /// 慢速动画持续时间 (350ms)
    static let slowDuration: Double = 0.35
    
    // MARK: 缓动函数
    
    /// 快速缓出动画
    static let fast = Animation.easeOut(duration: fastDuration)
    
    /// 正常动画持续时间
    static let normal = Animation.easeInOut(duration: normalDuration)
    
    /// 正常持续时间的缓入缓出动画
    static let easeInOut = Animation.easeInOut(duration: normalDuration)
    
    /// 默认使用临界阻尼，反馈迅速但不弹跳
    static let spring = Animation.spring(response: 0.3, dampingFraction: 1)
    
    /// 快速持续时间的柔和缓出动画
    static let gentle = Animation.easeOut(duration: fastDuration)
}

// MARK: - 设计字体

/// 文本层次的排版系统
/// 定义不同内容类型的字体样式
struct DesignFonts {
    /// 标题文本样式（半粗体）
    static let title = Font.title2.weight(.semibold)
    
    /// 标题文本样式（半粗体）
    static let headline = Font.headline.weight(.semibold)
    
    /// 正文文本样式（常规）
    static let body = Font.body
    
    /// 说明文本样式（小号）
    static let caption = Font.caption
    
    /// 输入字段文本样式（14pt 系统字体）
    static let input = Font.system(size: 14)
}
