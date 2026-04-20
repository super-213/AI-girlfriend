//
//  DialogWindowController.swift
//  看板娘
//
//  统一管理可复用对话窗口
//

import AppKit
import SwiftUI

final class DialogWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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
    }

    func closeDialog() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> DialogWindow {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        let window = DialogWindow(
            contentRect: frame,
            styleMask: [.borderless],
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

        let rootView = DialogChatView(
            viewModel: chatViewModel,
            onClose: { [weak self] in
                self?.closeDialog()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 30
        hostingView.layer?.masksToBounds = true

        window.contentView = hostingView
        window.center()
        return window
    }
}
