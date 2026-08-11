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
        let frame = NSRect(x: 0, y: 0, width: 1040, height: 680)
        let window = DialogWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "对话"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 760, height: 500)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed

        let rootView = DialogChatView(viewModel: chatViewModel)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        window.center()
        return window
    }
}
