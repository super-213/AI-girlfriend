//
//  PetApp.swift
//  桌面宠物应用
//
//  应用程序主入口和窗口配置
//

import SwiftUI

@main
struct PetApp: App {
    @StateObject private var backend = PetViewBackend()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Pet", id: "main-pet-window") {
            PetView(petViewBackend: backend)
                .frame(minWidth: 200, minHeight: 200)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置...") {
                    showPreferencesWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {}
        }
    }



    private func showPreferencesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)

        window.center()
        window.title = "偏好设置"
        window.isReleasedWhenClosed = false

        // 传入同一个 backend 实例
        window.contentView = NSHostingView(rootView: PreferencesView(petViewBackend: backend))
        window.makeKeyAndOrderFront(nil)
        window.level = .normal
    }
}

// MARK: - 应用委托

/// 应用程序委托，负责窗口配置和生命周期管理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置主窗口
        configureMainWindow()
        
        // 隐藏 Dock 图标（可选，如果想要纯悬浮效果）
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        configureMainWindow()
    }
    
    private func configureMainWindow() {
        guard let window = NSApplication.shared.windows.first(where: { 
            $0.title == "Pet" || $0.identifier?.rawValue == "main-pet-window" 
        }) ?? NSApplication.shared.windows.first else { return }
        
        applyTransparentStyle(to: window)
    }
    
    private func applyTransparentStyle(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
    }
}
