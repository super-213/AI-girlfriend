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
    @StateObject private var automationStore = AutomationStore.shared
    @StateObject private var triggerStore = TriggerStore.shared
    
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("provider") private var provider = "zhipu"
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3
    @AppStorage(PetHorizontalPlacement.storageKey) private var petHorizontalPlacement = PetHorizontalPlacement.defaultValue.rawValue
    @AppStorage("petSleepMinutes") private var sleepMinutes: Double = 6
    @AppStorage("commandConfirmationStyle") private var commandConfirmationStyle = "nearPet"
    @AppStorage("bubbleAutoHideDuration") private var bubbleAutoHideDuration: Double = 15
    
    @Environment(\.presentationMode) var presentationMode
    @State private var editingCharacterIndex: Int?
    @State private var modelConfigurations: [ModelConfiguration] = []
    @State private var originalModelConfigurations: [ModelConfiguration] = []
    @State private var selectedModelConfigurationID = ""
    @State private var activeModelConfigurationID = ""
    @State private var originalActiveModelConfigurationID = ""
    @State private var styleDraftSystemPrompt = ""
    @State private var styleDraftMessages: [String] = []
    @FocusState private var focusedField: FocusableField?
    
    /// 可聚焦字段枚举
    enum FocusableField: Hashable {
        case systemPrompt
        case provider
        case model
        case apiUrl
        case apiKey
    }
    
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _backend = StateObject(wrappedValue: PreferencesViewBackend(petViewBackend: petViewBackend))
    }

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .tint(DesignColors.primary)
            .accentColor(DesignColors.primary)
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 760, idealWidth: 860, maxWidth: 1_020, minHeight: 480, idealHeight: 560, maxHeight: 720)
            .onAppear(perform: handleAppear)
            .onReceive(NotificationCenter.default.publisher(for: .openPetPreferenceSection)) { notification in
                guard let rawValue = notification.object as? String,
                      let section = PreferencesViewBackend.PreferenceSection(rawValue: rawValue) else { return }
                backend.selectedSection = section
            }
            .onChange(of: [systemPrompt, String(overlapRatio), petHorizontalPlacement]) { _, _ in
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
        .alert("技能文件操作失败", isPresented: $backend.showSkillFileError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(backend.skillFileErrorMessage)
        }
        .alert("旧角色需要重新导入", isPresented: $backend.legacyCharactersNeedReimport) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("旧版角色索引已按当前设置清除，原素材文件仍保留在应用支持目录。请使用新格式重新导入。")
        }
        .sheet(isPresented: Binding(
            get: { editingCharacterIndex != nil },
            set: { if !$0 { editingCharacterIndex = nil } }
        )) {
            if let index = editingCharacterIndex, backend.customCharacters.indices.contains(index) {
                CharacterStateAssetsEditor(
                    character: backend.customCharacters[index],
                    onAdd: { state in showStateAssetPanel(characterIndex: index, state: state) },
                    onRemove: { state, assetID in
                        backend.removeStateAsset(fromCharacterAt: index, state: state, assetID: assetID)
                    },
                    onClose: { editingCharacterIndex = nil }
                )
            }
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
                systemPrompt: $styleDraftSystemPrompt,
                staticMessages: $styleDraftMessages,
                focusedField: $focusedField,
                onSave: saveStyleSettings,
                onCancel: restoreStyleDraft,
                hasUnsavedChanges: styleHasUnsavedChanges
            )
            
        case .model:
            ModelSettingsTab(
                configurations: $modelConfigurations,
                selectedConfigurationID: $selectedModelConfigurationID,
                activeConfigurationID: $activeModelConfigurationID,
                focusedField: $focusedField,
                onSave: saveModelSettings,
                onCancel: cancelChanges,
                hasUnsavedChanges: backend.hasUnsavedChanges || modelConfigurationsHaveUnsavedChanges
            )
            
        case .layout:
            LayoutSettingsTab(
                overlapRatio: $overlapRatio,
                petHorizontalPlacement: $petHorizontalPlacement,
                sleepMinutes: $sleepMinutes,
                commandConfirmationStyle: $commandConfirmationStyle,
                bubbleAutoHideDuration: $bubbleAutoHideDuration,
                character: petViewBackend.currentCharacter,
                onSave: saveSettings,
                onCancel: cancelChanges,
                hasUnsavedChanges: backend.hasUnsavedChanges
            )
            
        case .skills:
            SkillsSettingsTab(
                agentFile: backend.agentFile,
                skillFiles: backend.skillFiles,
                onImportAgent: showAgentImportDialog,
                onGenerateAgent: {
                    backend.generateDefaultAgentFile() ? backend.agentFile : nil
                },
                onRemoveAgent: backend.removeAgentFile,
                onImportSkills: showSkillImportDialog,
                onDeleteSkill: backend.deleteSkillFile(at:),
                onReadFile: backend.readMarkdownFile(at:),
                onSaveAgent: backend.saveAgentFileContent(_:),
                onSaveSkill: backend.saveSkillFileContent(id:content:),
                onCreateSkill: backend.createSkillFile(named:)
            )

        case .automation:
            AutomationSettingsTab(store: automationStore, triggerStore: triggerStore)

        case .triggers:
            TriggerSettingsTab(store: triggerStore)
            
        case .characterBinding:
            CharacterBindingTab(
                allCharacters: allCharacters,
                customCharacters: backend.customCharacters,
                builtInCharactersCount: availableCharacters.count,
                currentCharacterID: petViewBackend.currentCharacter.id,
                onCharacterChange: handleCharacterChange,
                onImport: { idleURL, interactionURL, name in
                    backend.importGIF(normalGif: idleURL, clickGif: interactionURL, name: name)
                },
                onDelete: backend.deleteCustomCharacter,
                onConfigure: { editingCharacterIndex = $0 },
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
        saveSettings(dismissAfterSave: true)
    }

    private func saveStyleSettings() {
        focusedField = nil
        systemPrompt = styleDraftSystemPrompt
        backend.staticMessages = styleDraftMessages
        saveSettings(dismissAfterSave: false)
    }

    private func restoreStyleDraft() {
        focusedField = nil
        styleDraftSystemPrompt = systemPrompt
        styleDraftMessages = backend.staticMessages
    }

    private func saveSettings(dismissAfterSave: Bool) {
        _ = backend.saveSettings(
            apiKey: apiKey,
            apiUrl: apiUrl,
            aiModel: aiModel,
            provider: provider,
            dismissAfterSave: dismissAfterSave,
            onSuccess: {
                backend.loadTemporaryValues(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio,
                    petHorizontalPlacement: petHorizontalPlacement
                )
            },
            onDismiss: {
                presentationMode.wrappedValue.dismiss()
            }
        )
    }

    private func saveModelSettings() {
        let normalizedConfigurations = modelConfigurations.map { $0.normalized() }
        guard let activeConfiguration = normalizedConfigurations.first(where: { $0.id == activeModelConfigurationID }) else {
            return
        }

        let library = ModelConfigurationLibrary(
            configurations: normalizedConfigurations,
            activeConfigurationID: activeModelConfigurationID
        )
        library.save()

        modelConfigurations = normalizedConfigurations
        originalModelConfigurations = normalizedConfigurations
        originalActiveModelConfigurationID = activeModelConfigurationID

        provider = activeConfiguration.provider
        aiModel = activeConfiguration.aiModel
        apiUrl = activeConfiguration.apiUrl
        apiKey = activeConfiguration.apiKey

        saveSettings(dismissAfterSave: false)
    }
    
    private func cancelChanges() {
        petHorizontalPlacement = backend.temporaryPetHorizontalPlacement
        backend.cancelChanges()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func handleAppear() {
        backend.selectedSection = AppWindowRouter.shared.pendingPreferenceSection
        petHorizontalPlacement = (PetHorizontalPlacement(rawValue: petHorizontalPlacement) ?? .defaultValue).rawValue

        let legacyConfiguration = ModelConfiguration.migratedLegacy(
            provider: provider,
            aiModel: aiModel,
            apiUrl: apiUrl,
            apiKey: apiKey
        )
        let library = ModelConfigurationLibrary.load(legacyConfiguration: legacyConfiguration)
        modelConfigurations = library.configurations
        originalModelConfigurations = library.configurations
        activeModelConfigurationID = library.activeConfigurationID
        originalActiveModelConfigurationID = library.activeConfigurationID
        selectedModelConfigurationID = library.activeConfigurationID

        backend.loadTemporaryValues(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            petHorizontalPlacement: petHorizontalPlacement
        )
        styleDraftSystemPrompt = systemPrompt
        styleDraftMessages = backend.staticMessages
    }
    
    private func checkChanges() {
        backend.checkUnsavedChanges(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            petHorizontalPlacement: petHorizontalPlacement
        )
    }
    
    private var modelConfigurationsHaveUnsavedChanges: Bool {
        modelConfigurations != originalModelConfigurations
            || activeModelConfigurationID != originalActiveModelConfigurationID
    }

    private var styleHasUnsavedChanges: Bool {
        styleDraftSystemPrompt != systemPrompt || styleDraftMessages != backend.staticMessages
    }
    
    private func handleCharacterChange(_ newIndex: Int) {
        backend.switchCharacter(to: newIndex)
    }
}

// MARK: - 角色状态素材

extension PreferencesView {
    private func showStateAssetPanel(characterIndex: Int, state: PetActivityState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif, .png, .jpeg]
        panel.message = "为“\(state.displayName)”选择素材"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _ = backend.addStateAsset(toCharacterAt: characterIndex, state: state, sourceURL: url)
        }
    }
}

// MARK: - Agent/Skill 导入对话框

extension PreferencesView {
    private func showAgentImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.markdown]
        panel.message = "选择 agent.md 文件"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _ = backend.importAgentFile(from: url)
        }
    }
    
    private func showSkillImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.markdown]
        panel.message = "选择一个或多个 skill.md 文件"
        
        panel.begin { response in
            guard response == .OK else { return }
            _ = backend.importSkillFiles(from: panel.urls)
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
    
    static var markdown: UTType {
        if let type = UTType(filenameExtension: "md") {
            return type
        }
        return .text
    }
}
