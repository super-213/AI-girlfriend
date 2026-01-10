//
//  PreferencesView.swift
//  桌面宠物应用
//
//  偏好设置视图，提供风格、模型、布局和角色绑定设置
//

import SwiftUI
import UniformTypeIdentifiers

/// 偏好设置主视图
/// 使用NavigationSplitView提供侧边栏导航和详情视图
struct PreferencesView: View {
    @ObservedObject var petViewBackend: PetViewBackend
    @StateObject private var backend: PreferencesViewBackend
    
    @AppStorage("apiKey") private var apiKey = "<默认API Key>f"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("provider") private var provider = "zhipu"
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3
    
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedIndex: Int = 0
    @FocusState private var focusedField: FocusableField?
    
    /// 可聚焦字段枚举
    enum FocusableField: Hashable {
        case systemPrompt
        case provider
        case model
        case apiUrl
        case apiKey
        case characterPicker
    }
    
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _backend = StateObject(wrappedValue: PreferencesViewBackend(petViewBackend: petViewBackend))
        _selectedIndex = State(initialValue: availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 600, idealWidth: 650, maxWidth: 800, minHeight: 400, idealHeight: 450, maxHeight: 600)
            .onAppear(perform: handleAppear)
            .onChange(of: [systemPrompt, String(overlapRatio)]) { _, _ in
                checkChanges()
            }
            
            if backend.showSuccessMessage {
                EnhancedSuccessBanner(message: "设置已成功保存")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .alert("保存失败", isPresented: $backend.showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(backend.errorAlertMessage)
        }
    }
}

// MARK: - 子视图

extension PreferencesView {
    private var sidebar: some View {
        List(PreferencesViewBackend.PreferenceSection.allCases, selection: $backend.selectedSection) { section in
            NavigationLink(value: section) {
                Label(section.rawValue, systemImage: section.icon)
            }
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
        .listStyle(.sidebar)
        .toolbar(removing: .sidebarToggle)
    }
    
    private var detailContent: some View {
        Group {
            if let section = backend.selectedSection {
                detailView(for: section)
                    .frame(minWidth: 400, minHeight: 350)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button(action: toggleSidebar) {
                                Image(systemName: "sidebar.left")
                            }
                            .help("切换侧边栏")
                        }
                    }
            } else {
                emptyDetailView
            }
        }
    }
    
    private var emptyDetailView: some View {
        Text("请选择一个设置项")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                    .help("切换侧边栏")
                }
            }
    }
}

// MARK: - 详情视图路由

extension PreferencesView {
    @ViewBuilder
    private func detailView(for section: PreferencesViewBackend.PreferenceSection) -> some View {
        switch section {
        case .style:
            StyleSettingsTab(
                systemPrompt: $systemPrompt,
                staticMessages: $backend.staticMessages,
                focusedField: $focusedField,
                onSave: saveSettings,
                onCancel: cancelChanges,
                hasUnsavedChanges: backend.hasUnsavedChanges
            )
            .onChange(of: backend.staticMessages) { _, _ in
                checkChanges()
            }
            
        case .model:
            ModelSettingsTab(
                provider: $provider,
                aiModel: $aiModel,
                apiUrl: $apiUrl,
                apiKey: $apiKey,
                focusedField: $focusedField,
                onProviderChange: handleProviderChange,
                onSave: saveSettings,
                onCancel: cancelChanges,
                hasUnsavedChanges: backend.hasUnsavedChanges
            )
            .onChange(of: aiModel) { _, _ in checkChanges() }
            .onChange(of: apiUrl) { _, _ in checkChanges() }
            .onChange(of: apiKey) { _, _ in checkChanges() }
            
        case .layout:
            LayoutSettingsTab(
                overlapRatio: $overlapRatio,
                onSave: saveSettings,
                onCancel: cancelChanges,
                hasUnsavedChanges: backend.hasUnsavedChanges
            )
            
        case .characterBinding:
            CharacterBindingTab(
                selectedIndex: $selectedIndex,
                focusedField: $focusedField,
                allCharacters: allCharacters,
                customCharacters: backend.customCharacters,
                availableCharactersCount: availableCharacters.count,
                onCharacterChange: handleCharacterChange,
                onImport: showImportDialog,
                onDelete: backend.deleteCustomCharacter,
                showImportError: $backend.showImportError,
                importErrorMessage: $backend.importErrorMessage
            )
            
        case .about:
            AboutTab(
                currentCharacterName: petViewBackend.currentCharacter.name,
                onClose: { presentationMode.wrappedValue.dismiss() }
            )
        }
    }
    
    private var allCharacters: [PetCharacter] {
        var characters = availableCharacters
        characters.append(contentsOf: backend.customCharacters)
        return characters
    }
}

// MARK: - 辅助方法

extension PreferencesView {
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    private func saveSettings() {
        _ = backend.saveSettings(
            apiKey: apiKey,
            apiUrl: apiUrl,
            aiModel: aiModel,
            provider: provider,
            onSuccess: {
                backend.loadTemporaryValues(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio
                )
            },
            onDismiss: {
                presentationMode.wrappedValue.dismiss()
            }
        )
    }
    
    private func cancelChanges() {
        backend.cancelChanges()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func handleAppear() {
        backend.loadTemporaryValues(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .systemPrompt
        }
    }
    
    private func checkChanges() {
        backend.checkUnsavedChanges(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio
        )
    }
    
    private func handleProviderChange(_ newProvider: String) {
        let result = backend.handleProviderChange(
            newProvider: newProvider,
            currentApiUrl: apiUrl,
            currentModel: aiModel
        )
        apiUrl = result.apiUrl
        aiModel = result.model
        checkChanges()
    }
    
    private func handleCharacterChange(_ newIndex: Int) {
        if newIndex < availableCharacters.count {
            backend.switchCharacter(to: newIndex)
        } else {
            let customIndex = newIndex - availableCharacters.count
            if customIndex < backend.customCharacters.count {
                petViewBackend.switchToCharacter(backend.customCharacters[customIndex])
            }
        }
    }
}

// MARK: - 导入对话框

extension PreferencesView {
    private func showImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif]
        panel.message = "选择站立GIF文件"
        
        panel.begin { response in
            guard response == .OK, let normalUrl = panel.url else { return }
            promptForCharacterName(normalUrl: normalUrl)
        }
    }
    
    private func promptForCharacterName(normalUrl: URL) {
        let alert = NSAlert()
        alert.messageText = "输入角色名称"
        alert.informativeText = "请为新角色输入一个名称"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.placeholderString = "角色名称"
        alert.accessoryView = inputField
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        let characterName = inputField.stringValue
        promptForClickGif(normalUrl: normalUrl, characterName: characterName)
    }
    
    private func promptForClickGif(normalUrl: URL, characterName: String) {
        let clickAlert = NSAlert()
        clickAlert.messageText = "选择动作GIF（可选）"
        clickAlert.informativeText = "是否为角色添加点击动作GIF？"
        clickAlert.addButton(withTitle: "选择")
        clickAlert.addButton(withTitle: "跳过")
        
        let clickResponse = clickAlert.runModal()
        
        if clickResponse == .alertFirstButtonReturn {
            selectClickGif(normalUrl: normalUrl, characterName: characterName)
        } else {
            _ = backend.importGIF(normalGif: normalUrl, clickGif: nil, name: characterName)
        }
    }
    
    private func selectClickGif(normalUrl: URL, characterName: String) {
        let clickPanel = NSOpenPanel()
        clickPanel.allowsMultipleSelection = false
        clickPanel.canChooseDirectories = false
        clickPanel.canChooseFiles = true
        clickPanel.allowedContentTypes = [.gif]
        clickPanel.message = "选择动作GIF文件"
        
        clickPanel.begin { clickPanelResponse in
            let clickUrl = clickPanelResponse == .OK ? clickPanel.url : nil
            _ = backend.importGIF(normalGif: normalUrl, clickGif: clickUrl, name: characterName)
        }
    }
}

// MARK: - UTType Extension

extension UTType {
    static var gif: UTType {
        if let type = UTType(filenameExtension: "gif") {
            return type
        }
        return .data
    }
}
