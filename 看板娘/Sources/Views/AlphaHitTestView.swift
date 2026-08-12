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

/// 通过后台预计算的素材 Alpha mask 判断是否命中角色。
/// 命中路径只做坐标换算和一次字节访问，不再同步渲染 SwiftUI 图层树。
class AlphaHitTestNSView: NSView, PetInteractiveRegion {
    override var isFlipped: Bool { true }

    var alphaMask: PetImageAlphaMask?
    var displayScale: CGFloat = 1
    var displayOffset: CGSize = .zero
    var artworkAlignmentOffset: CGFloat = 0

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor in
            PetWindowHitTestCoordinator.shared.register(self)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
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
        guard visibleRect.contains(localPoint) else { return false }
        guard let alphaMask else { return fallbackHitTest(localPoint) }
        return alphaMask.isOpaque(
            at: localPoint,
            in: bounds,
            displayScale: displayScale,
            displayOffset: displayOffset,
            artworkAlignmentOffset: artworkAlignmentOffset
        )
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

    /// 素材遮罩尚未在后台生成时，临时使用中心 60% 区域。
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
    var alphaMask: PetImageAlphaMask?
    var displayScale: CGFloat
    var displayOffset: CGSize
    var artworkAlignmentOffset: CGFloat

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
        view.alphaMask = alphaMask
        view.displayScale = displayScale
        view.displayOffset = displayOffset
        view.artworkAlignmentOffset = artworkAlignmentOffset
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
        let hitGeometryChanged = nsView.alphaMask !== alphaMask
            || nsView.displayScale != displayScale
            || nsView.displayOffset != displayOffset
            || nsView.artworkAlignmentOffset != artworkAlignmentOffset
        nsView.alphaMask = alphaMask
        nsView.displayScale = displayScale
        nsView.displayOffset = displayOffset
        nsView.artworkAlignmentOffset = artworkAlignmentOffset
        nsView.onTap = onTap
        nsView.onHover = onHover
        nsView.onDoubleTap = onDoubleTap
        nsView.onRightClick = onRightClick
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        if hitGeometryChanged {
            Task { @MainActor in
                PetWindowHitTestCoordinator.shared.refreshMousePolicy()
            }
        }
    }
}
