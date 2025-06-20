//___FILEHEADER___

import SwiftUI


@main
struct PetApp: App {
    @StateObject private var backend = PetViewBackend()

    var body: some Scene {
        WindowGroup {
            PetView(petViewBackend: backend)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
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
        }
    }

    private func showPreferencesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
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
