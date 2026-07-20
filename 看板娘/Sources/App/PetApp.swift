//
//  PetApp.swift
//  桌面宠物应用
//
//  应用程序主入口和窗口配置
//

import SwiftUI
import AppKit

@main
struct PetApp: App {
    @StateObject private var backend = PetViewBackend()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 初始化内存优化器
        _ = MemoryOptimizer.shared
    }

    var body: some Scene {
        Window("Pet", id: "main-pet-window") {
            PetView(petViewBackend: backend)
        }
        .windowStyle(.hiddenTitleBar)
        // 与桌宠 + 固定输入槽的基础尺寸一致，避免首次悬浮才触发窗口扩容。
        .defaultSize(width: 336, height: 346)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置...") {
                    AppWindowRouter.shared.showPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {}
        }

        MenuBarExtra("看板娘", systemImage: "pawprint.fill") {
            Button("打开完整对话") {
                AppWindowRouter.shared.showDialog()
            }
            Button("新建对话") {
                AppWindowRouter.shared.startNewDialog()
            }
            Divider()
            Button("偏好设置") {
                AppWindowRouter.shared.showPreferences()
            }
            Button("切换角色") {
                backend.cycleCharacter()
            }
            Button("自动化") {
                AppWindowRouter.shared.showPreferences(section: .automation)
            }
            Button("触发器") {
                AppWindowRouter.shared.showPreferences(section: .triggers)
            }
            Divider()
            Toggle("静音", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "petMuted") },
                set: { UserDefaults.standard.set($0, forKey: "petMuted") }
            ))
            Divider()
            Button("退出看板娘") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Notification.Name {
    static let openPetPreferenceSection = Notification.Name("openPetPreferenceSection")
}

@MainActor
final class AppWindowRouter {
    static let shared = AppWindowRouter()

    private weak var petViewBackend: PetViewBackend?
    private var preferencesWindow: NSWindow?
    private(set) var pendingPreferenceSection: PreferencesViewBackend.PreferenceSection = .style

    private init() {}

    func register(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
    }

    func showDialog() {
        DialogWindowController.shared.showDialog()
    }

    func startNewDialog() {
        DialogWindowController.shared.startNewConversation()
    }

    func showPreferences(section: PreferencesViewBackend.PreferenceSection = .style) {
        pendingPreferenceSection = section
        guard let backend = petViewBackend else { return }

        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "偏好设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(petViewBackend: backend))
            preferencesWindow = window
        }

        guard let preferencesWindow else { return }
        if preferencesWindow.isMiniaturized { preferencesWindow.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow.makeKeyAndOrderFront(nil)
        preferencesWindow.level = .normal
        NotificationCenter.default.post(name: .openPetPreferenceSection, object: section.rawValue)
    }
}

// MARK: - 应用委托

/// 应用程序委托，负责窗口配置和生命周期管理
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let dialogWindowController = DialogWindowController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置主窗口
        configureMainWindow()
        registerDialogHotkey()
        
        // 隐藏 Dock 图标（可选，如果想要纯悬浮效果）
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        configureMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterDialogHotkey()
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
        // 不使用 isMovableByWindowBackground，改为通过宠物图片区域（AlphaHitTestNSView）拖动
        // 避免拦截 chatBox 中 TextField 的点击事件
        window.isMovableByWindowBackground = false
        // 允许窗口接受鼠标移动事件，确保 hover 检测正常
        window.acceptsMouseMovedEvents = true
        
        // 隐藏红绿灯按钮（关闭、最小化、全屏）
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        PetWindowController.shared.attach(window: window)
    }

    private func registerDialogHotkey() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.matchesDialogHotkey(event) else { return event }

            self.dialogWindowController.showDialog()
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matchesDialogHotkey(event) else { return }
            DispatchQueue.main.async {
                self.dialogWindowController.showDialog()
            }
        }
    }

    private func unregisterDialogHotkey() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func matchesDialogHotkey(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.control] else { return false }

        return event.charactersIgnoringModifiers?.lowercased() == "t"
    }
}
