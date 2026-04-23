//
//  LayoutConstants.swift
//  桌面宠物应用
//
//  布局常量定义
//

import CoreGraphics

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

/// 宠物主界面与布局预览共用的几何参数
struct PetLayoutMetrics {
    let inputToChatSpacing: CGFloat
    let chatHeight: CGFloat
    let noOverlapSpacing: CGFloat
    let petFrameSize: CGFloat

    static let live = PetLayoutMetrics(
        inputToChatSpacing: 8,
        chatHeight: 80,
        noOverlapSpacing: 30,
        petFrameSize: 200
    )

    var maxOverlapTravel: CGFloat {
        chatHeight + noOverlapSpacing
    }

    func petTopSpacing(for overlapRatio: Double) -> CGFloat {
        let clampedRatio = min(max(CGFloat(overlapRatio), 0), 1)
        return maxOverlapTravel * (1 - clampedRatio)
    }

    func scaled(by scale: CGFloat) -> PetLayoutMetrics {
        PetLayoutMetrics(
            inputToChatSpacing: inputToChatSpacing * scale,
            chatHeight: chatHeight * scale,
            noOverlapSpacing: noOverlapSpacing * scale,
            petFrameSize: petFrameSize * scale
        )
    }
}
