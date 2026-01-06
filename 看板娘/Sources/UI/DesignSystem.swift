//
//  DesignSystem.swift
//  桌面宠物应用
//
//  界面增强的设计令牌和样式系统
//

import SwiftUI

// MARK: - 设计颜色

/// 应用的集中颜色系统
/// 为主要、次要、语义和基于状态的样式提供一致的颜色
struct DesignColors {
    // MARK: 主要颜色
    
    /// 主品牌颜色
    static let primary = Color.blue
    
    /// 悬停状态的主要颜色
    static let primaryHover = Color.blue.opacity(0.8)
    
    /// 激活/按下状态的主要颜色
    static let primaryActive = Color.blue.opacity(0.6)
    
    // MARK: 次要颜色
    
    /// 次要品牌颜色
    static let secondary = Color.gray
    
    /// 高亮的强调颜色
    static let accent = Color.pink
    
    // MARK: 语义颜色
    
    /// 成功状态颜色
    static let success = Color.green.opacity(0.8)
    
    /// 警告状态颜色
    static let warning = Color.yellow.opacity(0.8)
    
    /// 错误状态颜色
    static let error = Color.red.opacity(0.8)
    
    /// 信息状态颜色
    static let info = Color.blue.opacity(0.8)
    
    // MARK: 背景和表面颜色
    
    /// 浅色表面背景
    static let surfaceLight = Color.white.opacity(0.2)
    
    /// 中等表面背景
    static let surfaceMedium = Color.white.opacity(0.3)
    
    /// 深色表面背景
    static let surfaceHeavy = Color.white.opacity(0.4)
    
    // MARK: 文本颜色
    
    /// 主要文本颜色
    static let textPrimary = Color.primary
    
    /// 次要文本颜色
    static let textSecondary = Color.secondary
    
    /// 表面背景上的文本颜色
    static let textOnSurface = Color.white
    
    // MARK: 边框和分隔线颜色
    
    /// 默认边框颜色
    static let border = Color.gray.opacity(0.3)
    
    /// 焦点状态的边框颜色
    static let borderFocus = Color.blue.opacity(0.5)
    
    /// 错误状态的边框颜色
    static let borderError = Color.red.opacity(0.8)
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
    
    /// 自然弹跳的弹簧动画
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    /// 快速持续时间的柔和缓出动画
    static let gentle = Animation.easeOut(duration: fastDuration)
}

// MARK: - 设计字体

/// 文本层次的排版系统
/// 定义不同内容类型的字体样式
struct DesignFonts {
    /// 标题文本样式（粗体）
    static let title = Font.title.weight(.bold)
    
    /// 标题文本样式（半粗体）
    static let headline = Font.headline.weight(.semibold)
    
    /// 正文文本样式（常规）
    static let body = Font.body
    
    /// 说明文本样式（小号）
    static let caption = Font.caption
    
    /// 输入字段文本样式（14pt 系统字体）
    static let input = Font.system(size: 14)
}
