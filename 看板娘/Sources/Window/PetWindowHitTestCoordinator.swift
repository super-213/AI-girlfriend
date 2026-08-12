//
//  PetWindowHitTestCoordinator.swift
//  看板娘
//

import AppKit
import SwiftUI

@MainActor
protocol PetInteractiveRegion: AnyObject {
    var petInteractionFrameInScreen: NSRect? { get }
    func containsPetInteraction(at screenPoint: NSPoint) -> Bool
}

@MainActor
final class PetWindowHitTestCoordinator {
    static let shared = PetWindowHitTestCoordinator()

    private weak var window: NSWindow?
    private let regions = NSHashTable<NSView>.weakObjects()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var interactionLockCount = 0
    private var isResizeModeActive = false
    private let movementRefreshInterval: TimeInterval = 1.0 / 30.0
    private var lastMovementLocation: NSPoint?
    private var lastMovementRefreshTime: TimeInterval = -.infinity
    private var pendingMovementLocation: NSPoint?
    private var pendingMovementRefresh: DispatchWorkItem?

    private init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.scheduleMousePolicyRefresh(at: NSEvent.mouseLocation)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleMousePolicyRefresh(at: NSEvent.mouseLocation)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            pendingMovementRefresh?.cancel()
        }
    }

    func attach(window: NSWindow) {
        self.window = window
        refreshMousePolicy()
    }

    func register(_ region: NSView) {
        regions.add(region)
        refreshMousePolicy()
    }

    func unregister(_ region: NSView) {
        regions.remove(region)
        refreshMousePolicy()
    }

    func setInteractionLocked(_ locked: Bool) {
        interactionLockCount = max(interactionLockCount + (locked ? 1 : -1), 0)
        refreshMousePolicy()
    }

    func setResizeModeActive(_ active: Bool) {
        guard isResizeModeActive != active else { return }
        isResizeModeActive = active
        refreshMousePolicy()
    }

    func refreshMousePolicy() {
        pendingMovementRefresh?.cancel()
        pendingMovementRefresh = nil
        pendingMovementLocation = nil
        lastMovementRefreshTime = ProcessInfo.processInfo.systemUptime
        applyMousePolicy(at: NSEvent.mouseLocation)
    }

    private func scheduleMousePolicyRefresh(at mouseLocation: NSPoint) {
        // Local/global monitors can report the same physical movement. A policy
        // refresh cannot produce a different result while the pointer is still
        // at the same screen coordinate, so discard the duplicate immediately.
        guard lastMovementLocation != mouseLocation else { return }
        lastMovementLocation = mouseLocation
        pendingMovementLocation = mouseLocation

        guard pendingMovementRefresh == nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(movementRefreshInterval - (now - lastMovementRefreshTime), 0)
        if delay == 0 {
            performPendingMovementRefresh()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.performPendingMovementRefresh()
            }
        }
        pendingMovementRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performPendingMovementRefresh() {
        pendingMovementRefresh = nil
        guard let mouseLocation = pendingMovementLocation else { return }
        pendingMovementLocation = nil
        lastMovementRefreshTime = ProcessInfo.processInfo.systemUptime
        applyMousePolicy(at: mouseLocation)
    }

    private func applyMousePolicy(at mouse: NSPoint) {
        guard let window else { return }
        if interactionLockCount > 0 || isResizeModeActive {
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            return
        }

        let isInteractive = regions.allObjects.contains { view in
            guard let region = view as? PetInteractiveRegion,
                  let visibleFrame = region.petInteractionFrameInScreen,
                  visibleFrame.contains(mouse) else {
                return false
            }
            return region.containsPetInteraction(at: mouse)
        }
        let shouldIgnoreMouseEvents = !isInteractive
        if window.ignoresMouseEvents != shouldIgnoreMouseEvents {
            window.ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }
}

final class PetInteractionRegionNSView: NSView, PetInteractiveRegion {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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

    func containsPetInteraction(at screenPoint: NSPoint) -> Bool {
        guard let window, !isHiddenOrHasHiddenAncestor, alphaValue > 0.01 else { return false }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(pointInWindow, from: nil)
        return visibleRect.contains(localPoint)
    }

    var petInteractionFrameInScreen: NSRect? {
        guard let window,
              !isHiddenOrHasHiddenAncestor,
              alphaValue > 0.01,
              !visibleRect.isEmpty else { return nil }
        return window.convertToScreen(convert(visibleRect, to: nil))
    }
}

struct PetInteractiveRegionView: NSViewRepresentable {
    func makeNSView(context: Context) -> PetInteractionRegionNSView {
        PetInteractionRegionNSView(frame: .zero)
    }

    func updateNSView(_ nsView: PetInteractionRegionNSView, context: Context) {
        Task { @MainActor in
            PetWindowHitTestCoordinator.shared.refreshMousePolicy()
        }
    }
}

extension View {
    func petInteractiveRegion() -> some View {
        background(PetInteractiveRegionView())
    }
}
