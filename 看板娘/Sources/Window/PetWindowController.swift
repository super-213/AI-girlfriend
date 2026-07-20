//
//  PetWindowController.swift
//  看板娘
//

import AppKit
import SwiftUI

private struct PetWindowPlacement: Codable {
    let screenID: String
    let relativeCenterX: Double
    let relativeBottomY: Double
}

enum PetWindowSizing {
    static let minimumSize = NSSize(width: 180, height: 180)
    static let minimumContentScale: CGFloat = 0.5
    static let maximumContentScale: CGFloat = 2
}

/// 纯几何计算，内容变化时绝不改写宠物中心 X 与底部 Y。
struct PetWindowGeometry {
    static func anchoredFrame(
        currentFrame: NSRect,
        proposedContentSize: CGSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let size = NSSize(
            width: min(max(ceil(proposedContentSize.width), PetWindowSizing.minimumSize.width), visibleFrame.width),
            height: min(max(ceil(proposedContentSize.height), PetWindowSizing.minimumSize.height), visibleFrame.height)
        )
        let origin = NSPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.minY
        )
        return NSRect(origin: origin, size: size)
    }
}

struct PetWindowScaleGeometry {
    static func uniformlyResizedFrame(
        initialFrame: NSRect,
        proposedFrame: NSRect,
        edges: WindowResizeEdges,
        minimumSize: NSSize,
        visibleFrame: NSRect,
        minimumScaleFactor: CGFloat = 0,
        maximumScaleFactor: CGFloat = .greatestFiniteMagnitude
    ) -> NSRect {
        guard initialFrame.width > 0, initialFrame.height > 0 else { return proposedFrame }

        let widthScale = proposedFrame.width / initialFrame.width
        let heightScale = proposedFrame.height / initialFrame.height
        let hasHorizontalEdge = edges.contains(.left) || edges.contains(.right)
        let hasVerticalEdge = edges.contains(.top) || edges.contains(.bottom)

        let proposedScale: CGFloat
        if hasHorizontalEdge && hasVerticalEdge {
            proposedScale = abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
        } else if hasHorizontalEdge {
            proposedScale = widthScale
        } else {
            proposedScale = heightScale
        }

        let minimumScale = max(
            max(
                minimumSize.width / initialFrame.width,
                minimumSize.height / initialFrame.height
            ),
            minimumScaleFactor
        )

        let availableWidth: CGFloat
        if edges.contains(.left) {
            availableWidth = initialFrame.maxX - visibleFrame.minX
        } else if edges.contains(.right) {
            availableWidth = visibleFrame.maxX - initialFrame.minX
        } else {
            availableWidth = 2 * min(
                initialFrame.midX - visibleFrame.minX,
                visibleFrame.maxX - initialFrame.midX
            )
        }

        let availableHeight: CGFloat
        if edges.contains(.bottom) {
            availableHeight = initialFrame.maxY - visibleFrame.minY
        } else {
            availableHeight = visibleFrame.maxY - initialFrame.minY
        }

        let maximumScale = max(
            min(
                min(availableWidth / initialFrame.width, availableHeight / initialFrame.height),
                maximumScaleFactor
            ),
            minimumScale
        )
        let scale = min(max(proposedScale, minimumScale), maximumScale)
        let size = NSSize(
            width: initialFrame.width * scale,
            height: initialFrame.height * scale
        )

        let originX: CGFloat
        if edges.contains(.left) {
            originX = initialFrame.maxX - size.width
        } else if edges.contains(.right) {
            originX = initialFrame.minX
        } else {
            originX = initialFrame.midX - size.width / 2
        }

        let originY = edges.contains(.bottom)
            ? initialFrame.maxY - size.height
            : initialFrame.minY

        return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
    }
}

@MainActor
final class PetWindowController: ObservableObject {
    static let shared = PetWindowController()

    @Published private(set) var contentScale: CGFloat

    private weak var window: NSWindow?
    private weak var resizeOverlay: OptionWindowResizeNSView?
    private var attachedWindowNumber: Int?
    private var resizeWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var modifierPollTimer: Timer?
    private var localModifierEventMonitor: Any?
    private var globalModifierEventMonitor: Any?
    private var hasRestoredPlacement = false
    private var isResizeModeActive = false
    private var isUserResizing = false
    private var resizeStartFrame: NSRect?
    private var resizeStartScale: CGFloat = 1
    private var lastReportedContentSize: CGSize = .zero
    private var suppressContentResizeUntil: Date?
    private let placementKey = "petWindowPlacement.v2"
    private let contentScaleKey = "petWindowContentScale.v1"
    private let minimumContentScale = PetWindowSizing.minimumContentScale
    private let maximumContentScale = PetWindowSizing.maximumContentScale

    private init() {
        let savedScale = CGFloat(UserDefaults.standard.double(forKey: contentScaleKey))
        _contentScale = Published(
            initialValue: savedScale > 0
                ? min(max(savedScale, minimumContentScale), maximumContentScale)
                : 1
        )

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clampToVisibleScreen()
            }
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollOptionResizeMode()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierPollTimer = timer

        localModifierEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.setResizeModeActive(
                    event.modifierFlags
                        .intersection(.deviceIndependentFlagsMask)
                        .contains(.option)
                )
            }
            return event
        }

        globalModifierEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.setResizeModeActive(
                    event.modifierFlags
                        .intersection(.deviceIndependentFlagsMask)
                        .contains(.option)
                )
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        modifierPollTimer?.invalidate()
        if let localModifierEventMonitor { NSEvent.removeMonitor(localModifierEventMonitor) }
        if let globalModifierEventMonitor { NSEvent.removeMonitor(globalModifierEventMonitor) }
    }

    func attach(window: NSWindow) {
        self.window = window
        window.styleMask.remove(.resizable)
        window.contentMinSize = PetWindowSizing.minimumSize
        PetWindowHitTestCoordinator.shared.attach(window: window)
        installResizeOverlayIfNeeded(on: window)
        pollOptionResizeMode()

        guard attachedWindowNumber != window.windowNumber else { return }
        attachedWindowNumber = window.windowNumber
        window.acceptsMouseMovedEvents = true
        restorePlacementIfNeeded()
    }

    func reportContentSize(_ proposedSize: CGSize) {
        guard proposedSize.width > 0, proposedSize.height > 0 else { return }
        guard !isUserResizing else { return }
        if let suppressContentResizeUntil, Date() < suppressContentResizeUntil { return }

        self.suppressContentResizeUntil = nil
        lastReportedContentSize = proposedSize

        let scaledSize = CGSize(
            width: proposedSize.width * contentScale,
            height: proposedSize.height * contentScale
        )
        resizeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.resizeWindow(to: scaledSize)
            }
        }
        resizeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func setInteractionLocked(_ locked: Bool) {
        PetWindowHitTestCoordinator.shared.setInteractionLocked(locked)
    }

    func beginDragging() {
        setInteractionLocked(true)
    }

    func dragWindow(from initialOrigin: NSPoint, screenDelta: NSPoint) {
        guard let window else { return }
        let target = NSPoint(
            x: initialOrigin.x + screenDelta.x,
            y: initialOrigin.y + screenDelta.y
        )
        window.setFrameOrigin(clampedOrigin(target, for: window.frame.size, preferredScreen: screen(for: target)))
    }

    func endDragging() {
        savePlacement()
        setInteractionLocked(false)
    }

    private func installResizeOverlayIfNeeded(on window: NSWindow) {
        guard let currentContentView = window.contentView else { return }

        let container: WindowResizeContainerNSView
        if let existingContainer = currentContentView as? WindowResizeContainerNSView {
            container = existingContainer
        } else {
            let hostedContentView = currentContentView
            container = WindowResizeContainerNSView(frame: hostedContentView.frame)
            container.autoresizesSubviews = true
            window.contentView = container

            hostedContentView.frame = container.bounds
            hostedContentView.autoresizingMask = [.width, .height]
            container.addSubview(hostedContentView)
        }

        if let resizeOverlay, resizeOverlay.superview === container { return }

        self.resizeOverlay?.removeFromSuperview()
        let overlay = OptionWindowResizeNSView(frame: container.bounds)
        overlay.minimumSize = PetWindowSizing.minimumSize
        overlay.cornerRadius = 16
        overlay.autoresizingMask = [.width, .height]
        overlay.frameConstraint = { [weak self] initialFrame, proposedFrame, edges, visibleFrame in
            guard let self else { return proposedFrame }
            return self.constrainedResizeFrame(
                initialFrame: initialFrame,
                proposedFrame: proposedFrame,
                edges: edges,
                visibleFrame: visibleFrame
            )
        }
        overlay.onResizeBegan = { [weak self] frame in
            self?.beginUserResize(from: frame)
        }
        overlay.onResizeChanged = { [weak self] frame in
            self?.updateUserResize(to: frame)
        }
        overlay.onResizeEnded = { [weak self] frame in
            self?.endUserResize(at: frame)
        }
        // NSHostingView 会优先命中内部 SwiftUI 手势。边框必须与 hosting view
        // 成为普通容器中的兄弟视图，才能收到完整的拖拽事件序列。
        container.addSubview(overlay, positioned: .above, relativeTo: nil)
        resizeOverlay = overlay
        overlay.setResizeModeActive(isResizeModeActive)
    }

    private func pollOptionResizeMode() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        setResizeModeActive(flags.contains(.maskAlternate))
    }

    private func setResizeModeActive(_ active: Bool) {
        guard isResizeModeActive != active else { return }
        isResizeModeActive = active
        resizeOverlay?.setResizeModeActive(active)
        PetWindowHitTestCoordinator.shared.setResizeModeActive(active)
    }

    private func constrainedResizeFrame(
        initialFrame: NSRect,
        proposedFrame: NSRect,
        edges: WindowResizeEdges,
        visibleFrame: NSRect
    ) -> NSRect {
        PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initialFrame,
            proposedFrame: proposedFrame,
            edges: edges,
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visibleFrame,
            minimumScaleFactor: minimumContentScale / resizeStartScale,
            maximumScaleFactor: maximumContentScale / resizeStartScale
        )
    }

    private func beginUserResize(from frame: NSRect) {
        resizeWorkItem?.cancel()
        resizeStartFrame = frame
        resizeStartScale = contentScale
        isUserResizing = true
        setInteractionLocked(true)
    }

    private func updateUserResize(to frame: NSRect) {
        guard let resizeStartFrame, resizeStartFrame.width > 0 else { return }
        let scaleRatio = frame.width / resizeStartFrame.width
        contentScale = min(
            max(resizeStartScale * scaleRatio, minimumContentScale),
            maximumContentScale
        )
    }

    private func endUserResize(at frame: NSRect) {
        updateUserResize(to: frame)
        resizeStartFrame = nil
        isUserResizing = false
        // SwiftUI 在 scaleEffect 改变后的短暂布局周期里会报告反推后的临时尺寸。
        // 窗口已经由拖拽落在正确 frame 上，忽略这批报告，避免松手后又弹回去。
        suppressContentResizeUntil = Date().addingTimeInterval(0.25)
        UserDefaults.standard.set(Double(contentScale), forKey: contentScaleKey)
        savePlacement()
        setInteractionLocked(false)
    }

    func savePlacement() {
        guard let window, let screen = bestScreen(for: window.frame) else { return }
        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        let placement = PetWindowPlacement(
            screenID: screenIdentifier(screen),
            relativeCenterX: Double((window.frame.midX - visible.minX) / visible.width),
            relativeBottomY: Double((window.frame.minY - visible.minY) / visible.height)
        )
        guard let data = try? JSONEncoder().encode(placement) else { return }
        UserDefaults.standard.set(data, forKey: placementKey)
    }

    func clampToVisibleScreen() {
        guard let window else { return }
        let origin = clampedOrigin(window.frame.origin, for: window.frame.size, preferredScreen: bestScreen(for: window.frame))
        window.setFrameOrigin(origin)
    }

    private func resizeWindow(to proposedSize: CGSize) {
        guard let window else { return }
        let preferredScreen = bestScreen(for: window.frame) ?? NSScreen.main
        let visible = preferredScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 420, height: 700)
        let targetFrame = PetWindowGeometry.anchoredFrame(
            currentFrame: window.frame,
            proposedContentSize: proposedSize,
            visibleFrame: visible
        )

        guard abs(window.frame.width - targetFrame.width) > 0.5
                || abs(window.frame.height - targetFrame.height) > 0.5
                || abs(window.frame.minX - targetFrame.minX) > 0.5
                || abs(window.frame.minY - targetFrame.minY) > 0.5 else {
            return
        }

        // SwiftUI 浮层自行呈现；窗口 frame 不做插值，避免宠物在两套动画之间漂移。
        window.setFrame(targetFrame, display: true, animate: false)
        PetWindowHitTestCoordinator.shared.refreshMousePolicy()
    }

    private func restorePlacementIfNeeded() {
        guard !hasRestoredPlacement, let window else { return }
        hasRestoredPlacement = true
        guard let data = UserDefaults.standard.data(forKey: placementKey),
              let placement = try? JSONDecoder().decode(PetWindowPlacement.self, from: data) else {
            clampToVisibleScreen()
            return
        }

        let targetScreen = NSScreen.screens.first { screenIdentifier($0) == placement.screenID } ?? NSScreen.main
        guard let targetScreen else { return }
        let visible = targetScreen.visibleFrame
        let origin = NSPoint(
            x: visible.minX + CGFloat(placement.relativeCenterX) * visible.width - window.frame.width / 2,
            y: visible.minY + CGFloat(placement.relativeBottomY) * visible.height
        )
        window.setFrameOrigin(clampedOrigin(origin, for: window.frame.size, preferredScreen: targetScreen))
    }

    private func clampedOrigin(_ origin: NSPoint, for size: NSSize, preferredScreen: NSScreen?) -> NSPoint {
        guard let screen = preferredScreen ?? NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(max(origin.x, visible.minX), max(visible.maxX - size.width, visible.minX)),
            y: min(max(origin.y, visible.minY), max(visible.maxY - size.height, visible.minY))
        )
    }

    private func screen(for origin: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(origin) } ?? window?.screen ?? NSScreen.main
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        } ?? window?.screen ?? NSScreen.main
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}

private extension NSRect {
    var area: CGFloat { max(width, 0) * max(height, 0) }
}

struct PetWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                PetWindowController.shared.attach(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                PetWindowController.shared.attach(window: window)
            }
        }
    }
}

struct PetContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

extension View {
    func reportPetWindowContentSize() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: PetContentSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PetContentSizePreferenceKey.self) { size in
            PetWindowController.shared.reportContentSize(size)
        }
    }
}
