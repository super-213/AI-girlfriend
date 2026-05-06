//
//  AlphaHitTestView.swift
//  桌面宠物应用
//
//  透明像素点击穿透视图
//  只有点击到非透明像素时才响应点击事件
//

import SwiftUI
import AppKit

// MARK: - Alpha 点击检测 NSView

/// 自定义 NSView，通过渲染窗口 contentView 的 layer 来采样点击位置的 alpha 值，
/// 判断是否命中非透明区域
class AlphaHitTestNSView: NSView {
    /// 点击命中非透明区域时的回调
    var onTap: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // 尝试从窗口的 contentView layer 采样 alpha
        if let contentView = window?.contentView, let layer = contentView.layer {
            // 将点击坐标转换到 contentView 的坐标系
            let pointInContent = convert(localPoint, to: contentView)

            // 考虑 Retina 缩放
            let backingScale = window?.backingScaleFactor ?? 1.0
            let scaledX = pointInContent.x * backingScale
            let scaledY = (contentView.bounds.height - pointInContent.y) * backingScale // 翻转 Y 轴（layer 坐标系 Y 向下）

            // 创建 1x1 像素的 bitmap context
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0] // RGBA
            guard let ctx = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return fallbackHitTest(localPoint)
            }

            // 平移 context 使得目标像素位于原点
            ctx.translateBy(x: -scaledX, y: -scaledY)
            ctx.scaleBy(x: backingScale, y: backingScale)

            // 渲染整个 layer 到偏移后的 context（只有目标像素会被绘制）
            layer.render(in: ctx)

            // alpha > 30 视为非透明像素，响应点击
            if pixel[3] > 30 {
                return self
            }
            // 透明像素，穿透点击
            return nil
        }

        return fallbackHitTest(localPoint)
    }

    /// 兜底命中测试：如果 layer 渲染失败，使用中心 60% 区域
    private func fallbackHitTest(_ localPoint: NSPoint) -> NSView? {
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.2
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // 点击命中时触发回调
        onTap?()
    }
}

// MARK: - SwiftUI 桥接

/// 将 AlphaHitTestNSView 桥接到 SwiftUI 的 NSViewRepresentable
struct AlphaHitTestOverlay: NSViewRepresentable {
    /// 点击非透明区域时的回调
    var onTap: () -> Void

    func makeNSView(context: Context) -> AlphaHitTestNSView {
        let view = AlphaHitTestNSView()
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: AlphaHitTestNSView, context: Context) {
        nsView.onTap = onTap
    }
}
