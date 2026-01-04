//___FILEHEADER___

import SwiftUI


@main
struct PetApp: App {
    @StateObject private var backend = PetViewBackend()
<<<<<<< HEAD
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Pet", id: "main-pet-window") {
            PetView(petViewBackend: backend)
                .frame(minWidth: 200, minHeight: 200)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
=======

    var body: some Scene {
        WindowGroup {
            PetView(petViewBackend: backend)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置...") {
                    showPreferencesWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {}
<<<<<<< HEAD
            CommandGroup(replacing: .newItem) {}
=======
        }
    }

    init() {
        configureTransparentWindow()
    }

    private func configureTransparentWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.level = .floating
            }
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
        }
    }

    private func showPreferencesWindow() {
        let window = NSWindow(
<<<<<<< HEAD
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
=======
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)

        window.center()
        window.title = "偏好设置"
        window.isReleasedWhenClosed = false

        // 传入同一个 backend 实例
        window.contentView = NSHostingView(rootView: PreferencesView(backend: backend))
        window.makeKeyAndOrderFront(nil)
        window.level = .normal
    }
}
<<<<<<< HEAD

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置主窗口
        configureMainWindow()
        
        // 隐藏 Dock 图标（可选，如果想要纯悬浮效果）
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // 每次激活时确保窗口配置正确
        configureMainWindow()
    }
    
    private func configureMainWindow() {
        // 找到主窗口（第一个非偏好设置窗口）
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Pet" || $0.identifier?.rawValue == "main-pet-window" }) else {
            // 如果找不到特定窗口，使用第一个窗口
            guard let window = NSApplication.shared.windows.first else { return }
            applyTransparentStyle(to: window)
            return
        }
        
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
=======
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
