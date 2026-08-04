//
//  LayoutConstants.swift
//  桌面宠物应用
//
//  布局常量定义
//

import CoreGraphics

/// 桌宠相对于上方输入框和输出框的水平位置。
enum PetHorizontalPlacement: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    static let storageKey = "petHorizontalPlacement"
    static let defaultValue: PetHorizontalPlacement = .center

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "靠左"
        case .center: return "居中"
        case .right: return "靠右"
        }
    }

    var systemImage: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        }
    }
}

/// 布局常量，定义统一的间距和尺寸
struct LayoutConstants {
    static let sectionSpacing: CGFloat = 20
    static let fieldSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let textFieldWidth: CGFloat = 360
    static let textEditorMinHeight: CGFloat = 100
    static let systemPromptHeight: CGFloat = 240
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
}

/// 宠物主界面与布局预览共用的垂直几何参数。
///
/// `petStackSpacing` 是面板组（气泡、状态和输入框）与角色画布之间的
/// SwiftUI stack spacing。它可以为负数，让角色画布进入面板区域。
struct PetLayoutMetrics {
    let separatedSpacing: CGFloat
    let overlapTravel: CGFloat

    static let live = PetLayoutMetrics(
        separatedSpacing: 8,
        overlapTravel: 40
    )

    func petStackSpacing(for overlapRatio: Double) -> CGFloat {
        let clampedRatio = min(max(CGFloat(overlapRatio), 0), 1)
        return separatedSpacing - overlapTravel * clampedRatio
    }

    func scaled(by scale: CGFloat) -> PetLayoutMetrics {
        PetLayoutMetrics(
            separatedSpacing: separatedSpacing * scale,
            overlapTravel: overlapTravel * scale
        )
    }
}
