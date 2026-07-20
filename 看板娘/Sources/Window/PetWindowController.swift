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

/// 纯几何计算，内容变化时绝不改写宠物中心 X 与底部 Y。
struct PetWindowGeometry {
    static func anchoredFrame(
        currentFrame: NSRect,
        proposedContentSize: CGSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let size = NSSize(
            width: min(max(ceil(proposedContentSize.width), 220), visibleFrame.width),
            height: min(max(ceil(proposedContentSize.height), 220), visibleFrame.height)
        )
        let origin = NSPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.minY
        )
        return NSRect(origin: origin, size: size)
    }
}

@MainActor
final class PetWindowController {
    static let shared = PetWindowController()

    private weak var window: NSWindow?
    private var attachedWindowNumber: Int?
    private var resizeWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var hasRestoredPlacement = false
    private let placementKey = "petWindowPlacement.v2"

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clampToVisibleScreen()
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func attach(window: NSWindow) {
        self.window = window
        PetWindowHitTestCoordinator.shared.attach(window: window)

        guard attachedWindowNumber != window.windowNumber else { return }
        attachedWindowNumber = window.windowNumber
        window.contentMinSize = NSSize(width: 220, height: 220)
        window.acceptsMouseMovedEvents = true
        restorePlacementIfNeeded()
    }

    func reportContentSize(_ proposedSize: CGSize) {
        guard proposedSize.width > 0, proposedSize.height > 0 else { return }
        resizeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.resizeWindow(to: proposedSize)
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
