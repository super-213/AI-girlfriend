//___FILEHEADER___

import SwiftUI


@main
struct FloatingPetApp: App {
    @State private var showingPreferences = false
    var body: some Scene {
        WindowGroup {
            PetView() // 宠物视图
                .sheet(isPresented: $showingPreferences){
                    PreferencesView()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // 隐藏标题栏
        .commands {
            CommandGroup(replacing: .appSettings){
                Button("偏好设置...") {
                    showingPreferences.toggle()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {} // 隐藏菜单栏的多余选项
        }
    }

    init() {
        configureTransparentWindow()
    }

    private func configureTransparentWindow() {
        // 监听窗口设置
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titleVisibility = .hidden // 隐藏标题栏
                window.titlebarAppearsTransparent = true // 透明标题栏
                window.isOpaque = false // 窗口不透明
                window.backgroundColor = .clear // 背景透明
                window.hasShadow = false // 禁用窗口阴影
                window.level = .floating // 窗口置顶
                
                // 移除窗口的三个圈（最小化、最大化、关闭按钮）
                //window.styleMask.remove(.closable) // 去除关闭按钮
                //window.styleMask.remove(.resizable) // 去除调整大小按钮
                //window.styleMask.remove(.miniaturizable) // 去除最小化按钮
            }
        }
    }
}

