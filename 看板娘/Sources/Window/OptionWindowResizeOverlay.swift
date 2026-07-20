//
//  OptionWindowResizeOverlay.swift
//  看板娘
//
//  为无标题栏窗口提供按住 Option 后可见、可拖拽的调整尺寸边框。
//

import AppKit

struct WindowResizeEdges: OptionSet, Equatable {
    let rawValue: Int

    static let left = WindowResizeEdges(rawValue: 1 << 0)
    static let right = WindowResizeEdges(rawValue: 1 << 1)
    static let bottom = WindowResizeEdges(rawValue: 1 << 2)
    static let top = WindowResizeEdges(rawValue: 1 << 3)
}

struct WindowResizeGeometry {
    static func resizedFrame(
        initialFrame: NSRect,
        screenDelta: NSPoint,
        edges: WindowResizeEdges,
        minimumSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        var minX = initialFrame.minX
        var maxX = initialFrame.maxX
        var minY = initialFrame.minY
        var maxY = initialFrame.maxY

        if edges.contains(.left) {
            minX = clamp(
                initialFrame.minX + screenDelta.x,
                lowerBound: visibleFrame.minX,
                upperBound: initialFrame.maxX - minimumSize.width
            )
        } else if edges.contains(.right) {
            maxX = clamp(
                initialFrame.maxX + screenDelta.x,
                lowerBound: initialFrame.minX + minimumSize.width,
                upperBound: visibleFrame.maxX
            )
        }

        if edges.contains(.bottom) {
            minY = clamp(
                initialFrame.minY + screenDelta.y,
                lowerBound: visibleFrame.minY,
                upperBound: initialFrame.maxY - minimumSize.height
            )
        } else if edges.contains(.top) {
            maxY = clamp(
                initialFrame.maxY + screenDelta.y,
                lowerBound: initialFrame.minY + minimumSize.height,
                upperBound: visibleFrame.maxY
            )
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func clamp(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        guard lowerBound <= upperBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }
}

@MainActor
final class OptionWindowResizeNSView: NSView {
    var minimumSize = NSSize(width: 420, height: 320)
    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var frameConstraint: ((NSRect, NSRect, WindowResizeEdges, NSRect) -> NSRect)?
    var onResizeBegan: ((NSRect) -> Void)?
    var onResizeChanged: ((NSRect) -> Void)?
    var onResizeEnded: ((NSRect) -> Void)?

    private let hitInset: CGFloat = 12
    private let accentColor = NSColor(
        srgbRed: 0.89,
        green: 0.49,
        blue: 0.18,
        alpha: 1
    )
    private var activeEdges: WindowResizeEdges = []
    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?
    private var isOptionPressed = false {
        didSet {
            guard oldValue != isOptionPressed else { return }
            needsDisplay = true
            updateCursorForCurrentMouseLocation()
        }
    }

    private var isResizeDragActive: Bool {
        initialMouseLocation != nil && initialWindowFrame != nil && !activeEdges.isEmpty
    }

    private var shouldShowBorder: Bool {
        isOptionPressed || isResizeDragActive
    }

    var isResizeModeActive: Bool { isOptionPressed }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isOptionPressed, !resizeEdges(at: point).isEmpty else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard shouldShowBorder, bounds.width > 4, bounds.height > 4 else { return }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accentColor.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = .zero
        shadow.set()

        accentColor.setStroke()
        let borderRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(
            roundedRect: borderRect,
            xRadius: max(cornerRadius - 2, 0),
            yRadius: max(cornerRadius - 2, 0)
        )
        path.lineWidth = 2.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(at: point)
        guard isOptionPressed, !edges.isEmpty, let window else { return }

        activeEdges = edges
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window.frame
        needsDisplay = true
        onResizeBegan?(window.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialMouseLocation,
              let initialWindowFrame,
              !activeEdges.isEmpty else { return }

        let currentMouseLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: currentMouseLocation.x - initialMouseLocation.x,
            y: currentMouseLocation.y - initialMouseLocation.y
        )
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? initialWindowFrame
        let proposedFrame = WindowResizeGeometry.resizedFrame(
            initialFrame: initialWindowFrame,
            screenDelta: delta,
            edges: activeEdges,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame
        )
        let frame = frameConstraint?(
            initialWindowFrame,
            proposedFrame,
            activeEdges,
            visibleFrame
        ) ?? proposedFrame
        window.setFrame(frame, display: true, animate: false)
        onResizeChanged?(frame)
    }

    override func mouseUp(with event: NSEvent) {
        let finalFrame = window?.frame
        finishResizeDrag()
        if let finalFrame {
            onResizeEnded?(finalFrame)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateModifierFlags(event.modifierFlags)
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if !isResizeDragActive {
            NSCursor.arrow.set()
        }
    }

    func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
        setResizeModeActive(flags.intersection(.deviceIndependentFlagsMask).contains(.option))
    }

    func setResizeModeActive(_ active: Bool) {
        isOptionPressed = active
    }

    private func resizeEdges(at point: NSPoint) -> WindowResizeEdges {
        guard bounds.contains(point) else { return [] }

        var edges: WindowResizeEdges = []
        if point.x <= bounds.minX + hitInset { edges.insert(.left) }
        if point.x >= bounds.maxX - hitInset { edges.insert(.right) }
        if point.y <= bounds.minY + hitInset { edges.insert(.bottom) }
        if point.y >= bounds.maxY - hitInset { edges.insert(.top) }
        return edges
    }

    private func finishResizeDrag() {
        activeEdges = []
        initialMouseLocation = nil
        initialWindowFrame = nil
        needsDisplay = true
        updateCursorForCurrentMouseLocation()
    }

    private func updateCursorForCurrentMouseLocation() {
        guard let window else {
            NSCursor.arrow.set()
            return
        }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updateCursor(at: convert(pointInWindow, from: nil))
    }

    private func updateCursor(at point: NSPoint) {
        guard isOptionPressed else {
            if !isResizeDragActive { NSCursor.arrow.set() }
            return
        }

        let edges = resizeEdges(at: point)
        let isHorizontal = edges.contains(.left) || edges.contains(.right)
        let isVertical = edges.contains(.top) || edges.contains(.bottom)

        if isHorizontal && !isVertical {
            NSCursor.resizeLeftRight.set()
        } else if isVertical && !isHorizontal {
            NSCursor.resizeUpDown.set()
        } else if isHorizontal && isVertical {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
