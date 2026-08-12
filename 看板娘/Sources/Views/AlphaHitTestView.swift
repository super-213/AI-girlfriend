//
//  AlphaHitTestView.swift
//  桌面宠物应用
//
//  透明像素点击穿透视图
//  只有点击/悬停到非透明像素时才响应事件
//

import SwiftUI
import AppKit

// MARK: - Alpha 点击检测 NSView

/// 自定义 NSView，通过渲染窗口 contentView 的 layer 来采样位置的 alpha 值，
/// 判断是否命中非透明区域（用于点击和悬停检测）
class AlphaHitTestNSView: NSView, PetInteractiveRegion {
    private struct AlphaMask {
        let contentRect: NSRect
        let backingScale: CGFloat
        let pixelWidth: Int
        let pixelHeight: Int
        let bytesPerRow: Int
        let pixels: [UInt8]

        func isOpaque(at pointInContent: NSPoint) -> Bool {
            guard contentRect.contains(pointInContent) else { return false }

            let pixelX = min(
                max(Int((pointInContent.x - contentRect.minX) * backingScale), 0),
                pixelWidth - 1
            )
            // NSHostingView is flipped, while the bitmap context is bottom-up.
            // This is the cached equivalent of the previous per-pixel Y flip.
            let pixelY = min(
                max(Int((contentRect.maxY - pointInContent.y) * backingScale), 0),
                pixelHeight - 1
            )
            let alphaOffset = pixelY * bytesPerRow + pixelX * 2 + 1
            return pixels[alphaOffset] > 30
        }
    }

    private struct AlphaMaskGeometry: Equatable {
        let contentRect: NSRect
        let contentBounds: NSRect
        let backingScale: CGFloat
    }

    /// The window policy is refreshed at 30 Hz. Reusing the mask for the same
    /// interval lets policy, hover and click hit tests sample one animation-frame
    /// snapshot instead of independently rendering the full layer tree.
    private static let alphaMaskLifetime: TimeInterval = 1.0 / 30.0

    /// 点击命中非透明区域时的回调
    var onTap: (() -> Void)?

    var onDoubleTap: (() -> Void)?

    var onRightClick: (() -> Void)?

    var onDragBegan: (() -> Void)?

    var onDragChanged: ((NSPoint, NSPoint) -> Void)?

    var onDragEnded: (() -> Void)?
    
    /// 鼠标悬停状态变化回调（仅在非透明区域触发）
    var onHover: ((Bool) -> Void)?
    
    /// 当前是否处于"命中非透明区域"的悬停状态
    private var isHovering = false
    
    /// 鼠标追踪区域
    private var trackingArea: NSTrackingArea?

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var didDrag = false
    private var cachedAlphaMask: AlphaMask?
    private var cachedAlphaMaskGeometry: AlphaMaskGeometry?
    private var cachedAlphaMaskCreationTime: TimeInterval = -.infinity

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateAlphaMask()
        guard window != nil else { return }
        Task { @MainActor in
            PetWindowHitTestCoordinator.shared.register(self)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        invalidateAlphaMask()
        if window != nil, newWindow == nil {
            Task { @MainActor in
                PetWindowHitTestCoordinator.shared.unregister(self)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // 移除旧的追踪区域
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // 创建新的追踪区域，监听鼠标移动、进入和退出
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard visibleRect.contains(point) else { return nil }

        if isPointOpaque(point) {
            return self
        }
        // 透明像素，穿透点击
        return nil
    }
    
    // MARK: - 鼠标悬停事件
    
    override func mouseEntered(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        updateHoverState(at: localPoint)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        updateHoverState(at: localPoint)
    }
    
    override func mouseExited(with event: NSEvent) {
        if isHovering {
            isHovering = false
            onHover?(false)
        }
    }
    
    // MARK: - 点击事件

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseLocation, let initialWindowOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - initialMouseLocation.x, y: current.y - initialMouseLocation.y)

        if !didDrag, hypot(delta.x, delta.y) >= 4 {
            didDrag = true
            onDragBegan?()
        }
        if didDrag {
            onDragChanged?(initialWindowOrigin, delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            initialMouseLocation = nil
            initialWindowOrigin = nil
            didDrag = false
        }

        if didDrag {
            onDragEnded?()
        } else if event.clickCount >= 2 {
            onDoubleTap?()
        } else {
            onTap?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
    
    // MARK: - Alpha 检测核心逻辑
    
    /// 判断指定本地坐标点是否为非透明像素
    private func isPointOpaque(_ localPoint: NSPoint) -> Bool {
        // First reject points outside the clipped visible region. Most desktop
        // mouse movement never reaches the more expensive alpha path.
        guard visibleRect.contains(localPoint) else { return false }

        guard let contentView = window?.contentView, let layer = contentView.layer else {
            return fallbackHitTest(localPoint)
        }

        let pointInContent = convert(localPoint, to: contentView)
        let backingScale = window?.backingScaleFactor ?? 1.0
        let visibleContentRect = convert(visibleRect, to: contentView).standardized
            .intersection(contentView.bounds)
        guard !visibleContentRect.isEmpty else { return false }

        let geometry = AlphaMaskGeometry(
            contentRect: visibleContentRect,
            contentBounds: contentView.bounds,
            backingScale: backingScale
        )
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedAlphaMask,
           cachedAlphaMaskGeometry == geometry,
           now - cachedAlphaMaskCreationTime < Self.alphaMaskLifetime {
            return cachedAlphaMask.isOpaque(at: pointInContent)
        }

        guard let mask = makeAlphaMask(
            layer: layer,
            contentRect: visibleContentRect,
            backingScale: backingScale
        ) else {
            invalidateAlphaMask()
            return fallbackHitTest(localPoint)
        }

        cachedAlphaMask = mask
        cachedAlphaMaskGeometry = geometry
        cachedAlphaMaskCreationTime = now
        return mask.isOpaque(at: pointInContent)
    }

    private func makeAlphaMask(
        layer: CALayer,
        contentRect: NSRect,
        backingScale: CGFloat
    ) -> AlphaMask? {
        let pixelWidth = max(Int(ceil(contentRect.width * backingScale)), 1)
        let pixelHeight = max(Int(ceil(contentRect.height * backingScale)), 1)
        let bytesPerPixel = 2 // grayscale + alpha
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)

        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            let scaledMinX = contentRect.minX * backingScale
            let scaledMinY = contentRect.minY * backingScale
            context.translateBy(x: -scaledMinX, y: -scaledMinY)
            context.scaleBy(x: backingScale, y: backingScale)
            layer.render(in: context)
            return true
        }
        guard rendered else { return nil }

        return AlphaMask(
            contentRect: contentRect,
            backingScale: backingScale,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bytesPerRow: bytesPerRow,
            pixels: pixels
        )
    }

    private func invalidateAlphaMask() {
        cachedAlphaMask = nil
        cachedAlphaMaskGeometry = nil
        cachedAlphaMaskCreationTime = -.infinity
    }

    func containsPetInteraction(at screenPoint: NSPoint) -> Bool {
        guard let window, !isHiddenOrHasHiddenAncestor, alphaValue > 0.01 else { return false }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(pointInWindow, from: nil)
        return visibleRect.contains(localPoint) && isPointOpaque(localPoint)
    }

    var petInteractionFrameInScreen: NSRect? {
        guard let window,
              !isHiddenOrHasHiddenAncestor,
              alphaValue > 0.01,
              !visibleRect.isEmpty else { return nil }
        return window.convertToScreen(convert(visibleRect, to: nil))
    }

    /// 兜底命中测试：如果 layer 渲染失败，使用中心 60% 区域
    private func fallbackHitTest(_ localPoint: NSPoint) -> Bool {
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.2
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint)
    }
    
    /// 根据当前鼠标位置更新悬停状态
    private func updateHoverState(at localPoint: NSPoint) {
        let opaque = bounds.contains(localPoint) && isPointOpaque(localPoint)
        
        if opaque && !isHovering {
            isHovering = true
            onHover?(true)
        } else if !opaque && isHovering {
            isHovering = false
            onHover?(false)
        }
    }
}

// MARK: - SwiftUI 桥接

/// 将 AlphaHitTestNSView 桥接到 SwiftUI 的 NSViewRepresentable
struct AlphaHitTestOverlay: NSViewRepresentable {
    /// 点击非透明区域时的回调
    var onTap: () -> Void
    
    /// 鼠标悬停非透明区域状态变化回调
    var onHover: ((Bool) -> Void)?

    var onDoubleTap: (() -> Void)?

    var onRightClick: (() -> Void)?

    var onDragBegan: (() -> Void)?

    var onDragChanged: ((NSPoint, NSPoint) -> Void)?

    var onDragEnded: (() -> Void)?

    func makeNSView(context: Context) -> AlphaHitTestNSView {
        let view = AlphaHitTestNSView()
        view.onTap = onTap
        view.onHover = onHover
        view.onDoubleTap = onDoubleTap
        view.onRightClick = onRightClick
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: AlphaHitTestNSView, context: Context) {
        nsView.onTap = onTap
        nsView.onHover = onHover
        nsView.onDoubleTap = onDoubleTap
        nsView.onRightClick = onRightClick
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}
