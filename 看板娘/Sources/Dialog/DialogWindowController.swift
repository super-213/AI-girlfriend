//
//  DialogWindowController.swift
//  看板娘
//
//  统一管理可复用对话窗口
//

import AppKit
import SwiftUI

@MainActor
final class DialogWindow: NSWindow {
    weak var resizeOverlay: OptionWindowResizeNSView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            updateResizeMode(for: event.modifierFlags)
        }
        super.sendEvent(event)
    }

    func updateResizeMode(for modifierFlags: NSEvent.ModifierFlags) {
        resizeOverlay?.updateModifierFlags(modifierFlags)
    }
}

@MainActor
final class DialogWindowController {
    static let shared = DialogWindowController()

    private let chatViewModel = DialogChatViewModel()
    private var window: DialogWindow?

    private init() {}

    func showDialog() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }
        if !window.isVisible {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.updateResizeMode(for: NSEvent.modifierFlags)
    }

    func closeDialog() {
        window?.updateResizeMode(for: [])
        window?.orderOut(nil)
    }

    func startNewConversation() {
        chatViewModel.startNewConversation()
        showDialog()
    }

    private func makeWindow() -> DialogWindow {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        let window = DialogWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "对话"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 420, height: 320)

        let rootView = DialogChatView(
            viewModel: chatViewModel,
            onClose: { [weak self] in
                self?.closeDialog()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 30
        hostingView.layer?.masksToBounds = true

        let resizeOverlay = OptionWindowResizeNSView(frame: hostingView.bounds)
        resizeOverlay.minimumSize = window.contentMinSize
        resizeOverlay.cornerRadius = 30
        resizeOverlay.autoresizingMask = [.width, .height]

        let containerView = NSView(frame: hostingView.frame)
        containerView.autoresizesSubviews = true
        containerView.addSubview(hostingView)
        containerView.addSubview(resizeOverlay, positioned: .above, relativeTo: hostingView)

        window.resizeOverlay = resizeOverlay
        window.contentView = containerView
        window.updateResizeMode(for: NSEvent.modifierFlags)
        window.center()
        return window
    }
}
