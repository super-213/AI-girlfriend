//
//  LayoutConstants.swift
//  桌面宠物应用
//
//  布局常量定义
//

import CoreGraphics
import Foundation
import SwiftUI

/// 桌宠相对于上方输入框和输出框的连续水平位置。
///
/// `0` 表示最左侧，`0.5` 表示居中，`1` 表示最右侧。
enum PetHorizontalPosition {
    static let storageKey = "petHorizontalPosition"
    static let legacyStorageKey = "petHorizontalPlacement"
    static let defaultValue = 0.5
    static let range = 0.0...1.0

    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func percentage(for value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }

    static func leadingOffset(
        containerWidth: CGFloat,
        contentWidth: CGFloat,
        position: Double
    ) -> CGFloat {
        max(containerWidth - contentWidth, 0) * CGFloat(clamped(position))
    }

    /// 将旧版 left / center / right 三档设置迁移为连续位置。
    static func migrateStorage(in defaults: UserDefaults = .standard) {
        if let storedNumber = defaults.object(forKey: storageKey) as? NSNumber {
            let normalizedValue = clamped(storedNumber.doubleValue)
            if normalizedValue != storedNumber.doubleValue {
                defaults.set(normalizedValue, forKey: storageKey)
            }
            return
        }

        let migratedValue: Double
        switch defaults.string(forKey: legacyStorageKey) {
        case "left": migratedValue = 0
        case "right": migratedValue = 1
        default: migratedValue = defaultValue
        }
        defaults.set(migratedValue, forKey: storageKey)
    }
}

/// 在可用宽度内按归一化位置连续放置单个子视图。
struct PetHorizontalPositionLayout: Layout {
    let position: Double

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let contentSize = subview.sizeThatFits(.unspecified)
        return CGSize(
            width: proposal.width ?? contentSize.width,
            height: proposal.height ?? contentSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let contentSize = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(
                x: bounds.minX + PetHorizontalPosition.leadingOffset(
                    containerWidth: bounds.width,
                    contentWidth: contentSize.width,
                    position: position
                ),
                y: bounds.midY
            ),
            anchor: .leading,
            proposal: ProposedViewSize(contentSize)
        )
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
