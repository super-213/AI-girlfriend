//
//  PetWindowHitTestCoordinator.swift
//  看板娘
//

import AppKit
import SwiftUI

protocol PetInteractiveRegion: AnyObject {
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

    private init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.refreshMousePolicy()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshMousePolicy()
            }
        }
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
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
        guard let window else { return }
        if interactionLockCount > 0 || isResizeModeActive {
            window.ignoresMouseEvents = false
            return
        }

        let mouse = NSEvent.mouseLocation
        let isInteractive = regions.allObjects.contains { view in
            (view as? PetInteractiveRegion)?.containsPetInteraction(at: mouse) == true
        }
        window.ignoresMouseEvents = !isInteractive
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
        guard let window, !isHidden, alphaValue > 0.01 else { return false }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(pointInWindow, from: nil)
        return bounds.contains(localPoint)
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
