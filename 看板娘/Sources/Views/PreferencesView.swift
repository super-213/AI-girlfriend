//
//  PreferencesView.swift
//  桌面宠物应用
//
//  偏好设置视图，提供风格、模型、布局和角色绑定设置
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 偏好设置视图

/// 偏好设置主视图
/// 使用NavigationSplitView提供侧边栏导航和详情视图
struct PreferencesView: View {
    // MARK: - 属性

    @ObservedObject var petViewBackend: PetViewBackend
    @StateObject private var backend: PreferencesViewBackend

    // MARK: - 应用存储

    @AppStorage("apiKey") private var apiKey = "<默认API Key>f"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("provider") private var provider = "zhipu"
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3

    // MARK: - 环境

    @Environment(\.presentationMode) var presentationMode

    // MARK: - 状态

    /// 当前选中的角色索引
    @State private var selectedIndex: Int = 0
    
    /// 当前聚焦的输入字段
    @FocusState private var focusedField: FocusableField?
    
    /// 计算属性：获取所有角色（包括自定义角色）
    private var allCharacters: [PetCharacter] {
        var characters = availableCharacters
        characters.append(contentsOf: backend.customCharacters)
        return characters
    }
    
    /// 可聚焦字段枚举
    enum FocusableField: Hashable {
        case systemPrompt
        case provider
        case model
        case apiUrl
        case apiKey
        case characterPicker
    }

    // MARK: - 初始化

    /// 初始化偏好设置视图
    /// - Parameter petViewBackend: 宠物视图后端实例
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _backend = StateObject(wrappedValue: PreferencesViewBackend(petViewBackend: petViewBackend))
        _selectedIndex = State(initialValue: availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0)
    }

    // MARK: - 主体

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                // 侧边栏
                List(PreferencesViewBackend.PreferenceSection.allCases, selection: $backend.selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
                .listStyle(.sidebar)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                // 详情视图
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
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 600, idealWidth: 650, maxWidth: 800, minHeight: 400, idealHeight: 450, maxHeight: 600)
            .onAppear {
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
            .onChange(of: [systemPrompt, String(overlapRatio)]) { _, _ in
                backend.checkUnsavedChanges(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio
                )
            }
            
            // 成功消息横幅
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
    
    // MARK: - 详情视图
    
    @ViewBuilder
    private func detailView(for section: PreferencesViewBackend.PreferenceSection) -> some View {
        switch section {
        case .style:
            styleSettingsTab
        case .model:
            modelSettingsTab
        case .layout:
            layoutSettingsTab
        case .characterBinding:
            characterBindingTab
        case .about:
            aboutTab
        }
    }
    
    // MARK: - 辅助方法
    
    /// 切换侧边栏显示/隐藏
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    /// 保存设置
    private func saveSettings() {
        _ = backend.saveSettings(
            apiKey: apiKey,
            apiUrl: apiUrl,
            aiModel: aiModel,
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
    
    /// 取消更改，恢复到之前的值
    private func cancelChanges() {
        apiKey = backend.tempApiKey
        aiModel = backend.tempAiModel
        systemPrompt = backend.tempSystemPrompt
        apiUrl = backend.tempApiUrl
        provider = backend.tempProvider
        overlapRatio = backend.tempOverlapRatio
        backend.cancelChanges()
    }

    // MARK: - 标签页

    /// 风格设置标签页
    private var styleSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                SystemPromptEditor(
                    text: $systemPrompt,
                    defaultPrompt: PreferencesData.default.systemPrompt,
                    focusedField: $focusedField
                )
                .accessibilityLabel("系统提示词编辑器")
                .accessibilityHint("编辑 AI 角色的个性和行为设置")

                Spacer()

                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: !backend.validationState.isValid,
                    hasUnsavedChanges: backend.hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("风格设置标签")
    }

    /// 模型设置标签页
    private var modelSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                // 提供商选择器
                ProviderPicker(selectedProvider: $provider)
                    .accessibilityLabel("AI 服务提供商选择器")
                    .accessibilityHint("选择智谱清言或通义千问作为 AI 服务提供商")
                    .focused($focusedField, equals: .provider)
                    .onChange(of: provider) { _, newValue in
                        let result = backend.handleProviderChange(
                            newProvider: newValue,
                            currentApiUrl: apiUrl,
                            currentModel: aiModel
                        )
                        apiUrl = result.apiUrl
                        aiModel = result.model
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                    }
                
                // 模型字段
                EnhancedFormField(
                    label: "模型：",
                    errorMessage: backend.validationErrors["model"],
                    successMessage: backend.validationErrors["model"] == nil && !aiModel.isEmpty ? "模型名称有效" : nil
                ) {
                    TextField(
                        provider == "zhipu" ? "例如: glm-4v-flash" : "例如: qwen-turbo",
                        text: $aiModel
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: LayoutConstants.textFieldWidth)
                    .focused($focusedField, equals: .model)
                    .accessibilityLabel("AI 模型名称")
                    .accessibilityHint(
                        provider == "zhipu" 
                            ? "输入智谱清言的模型名称，例如 glm-4v-flash"
                            : "输入通义千问的模型名称，例如 qwen-turbo"
                    )
                    .onChange(of: aiModel) { _, _ in
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                        backend.validateModelRealtime(aiModel)
                    }
                }

                // API 地址字段
                EnhancedFormField(
                    label: "API 地址：",
                    errorMessage: backend.validationErrors["apiUrl"],
                    successMessage: backend.validationErrors["apiUrl"] == nil && !apiUrl.isEmpty ? "URL 格式正确" : nil
                ) {
                    TextField(
                        provider == "zhipu" 
                            ? "例如: https://open.bigmodel.cn/api/paas/v4/..." 
                            : "例如: https://dashscope.aliyuncs.com/api/v1/...",
                        text: $apiUrl
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: LayoutConstants.textFieldWidth)
                    .focused($focusedField, equals: .apiUrl)
                    .accessibilityLabel("API 服务地址")
                    .accessibilityHint("输入 AI 服务的 API 地址，必须是 HTTPS 协议")
                    .onChange(of: apiUrl) { _, _ in
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                        backend.validateAPIURLRealtime(apiUrl)
                    }
                }

                // API Key 字段
                EnhancedFormField(
                    label: "API Key:",
                    errorMessage: backend.validationErrors["apiKey"],
                    successMessage: backend.validationErrors["apiKey"] == nil && !apiKey.isEmpty && !apiKey.contains("<默认API Key>") ? "API Key 有效" : nil
                ) {
                    TextEditor(text: $apiKey)
                        .frame(height: LayoutConstants.textEditorMinHeight)
                        .border(
                            backend.validationErrors["apiKey"] != nil ? Color.errorRed : Color.borderGray,
                            width: LayoutConstants.borderWidth
                        )
                        .font(FontStyles.fieldInput)
                        .focused($focusedField, equals: .apiKey)
                        .accessibilityLabel("API 密钥")
                        .accessibilityHint("输入您的 API 密钥以访问 AI 服务")
                        .onChange(of: apiKey) { _, _ in
                            backend.checkUnsavedChanges(
                                apiKey: apiKey,
                                aiModel: aiModel,
                                systemPrompt: systemPrompt,
                                apiUrl: apiUrl,
                                provider: provider,
                                overlapRatio: overlapRatio
                            )
                            backend.validateAPIKeyRealtime(apiKey)
                        }
                }

                Spacer()

                // 操作按钮
                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: !backend.validationState.isValid,
                    hasUnsavedChanges: backend.hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模型设置标签")
    }

    /// 布局设置标签页
    private var layoutSettingsTab: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                Text("调整界面重叠比例")
                    .font(DesignFonts.headline)
                    .padding(.top, DesignSpacing.md)
                
                // 预览区域
                OverlapPreview(overlapRatio: overlapRatio)
                    .frame(height: 180)
                    .padding(.horizontal, DesignSpacing.lg)
                
                // 滑块控制
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    HStack {
                        Text("重叠比例:")
                            .font(DesignFonts.body)
                        Spacer()
                        Text("\(Int(overlapRatio * 100))%")
                            .font(DesignFonts.body.monospacedDigit())
                            .foregroundColor(DesignColors.textSecondary)
                    }
                    
                    Slider(value: $overlapRatio, in: 0...1, step: 0.01)
                        .accessibilityLabel("重叠比例滑块")
                        .accessibilityValue("\(Int(overlapRatio * 100))%")
                    
                    HStack {
                        Text("0% (不重叠)")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                        Spacer()
                        Text("100% (完全重叠)")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSpacing.xl)
                
                Spacer()
                
                // 操作按钮
                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: false,
                    hasUnsavedChanges: backend.hasUnsavedChanges
                )
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局设置标签")
    }

    /// 角色绑定标签页
    private var characterBindingTab: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                Text("角色绑定管理")
                    .font(DesignFonts.title)
                    .padding(.top, DesignSpacing.md)
                
                // 角色选择器部分
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    Text("当前角色：")
                        .font(DesignFonts.headline)
                        .foregroundColor(DesignColors.textPrimary)
                    
                    Picker("选择角色", selection: $selectedIndex) {
                        ForEach(0..<allCharacters.count, id: \.self) { index in
                            Text(allCharacters[index].name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .focused($focusedField, equals: .characterPicker)
                    .accessibilityLabel("角色选择器")
                    .accessibilityHint("选择不同的桌面宠物角色")
                    .onChange(of: selectedIndex) { _, newValue in
                        if newValue < availableCharacters.count {
                            backend.switchCharacter(to: newValue)
                        } else {
                            // 切换到自定义角色
                            let customIndex = newValue - availableCharacters.count
                            if customIndex < backend.customCharacters.count {
                                petViewBackend.switchToCharacter(backend.customCharacters[customIndex])
                            }
                        }
                    }
                    
                    // 角色数量显示
                    HStack(spacing: DesignSpacing.xs) {
                        Image(systemName: "person.2.fill")
                            .font(DesignFonts.caption)
                        Text("可用角色: \(allCharacters.count) 个 (内置: \(availableCharacters.count), 自定义: \(backend.customCharacters.count))")
                            .font(DesignFonts.caption)
                    }
                    .foregroundColor(DesignColors.textSecondary)
                }
                .padding(.horizontal, DesignSpacing.xl)
                
                Divider()
                    .padding(.vertical, DesignSpacing.md)
                
                // 自定义角色管理
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    HStack {
                        Text("自定义角色 (\(backend.customCharacters.count)/3)")
                            .font(DesignFonts.headline)
                        Spacer()
                        Button(action: {
                            // 导入新角色
                            showImportDialog()
                        }) {
                            Label("导入", systemImage: "plus.circle.fill")
                        }
                        .disabled(backend.customCharacters.count >= 3)
                    }
                    
                    if backend.customCharacters.isEmpty {
                        Text("暂无自定义角色，点击导入按钮添加")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignSpacing.lg)
                    } else {
                        ForEach(Array(backend.customCharacters.enumerated()), id: \.offset) { index, character in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(DesignFonts.body)
                                    Text("站立: \(URL(fileURLWithPath: character.normalGif).lastPathComponent)")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textSecondary)
                                    Text("动作: \(URL(fileURLWithPath: character.clickGif).lastPathComponent)")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textSecondary)
                                }
                                Spacer()
                                Button(action: {
                                    backend.deleteCustomCharacter(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, DesignSpacing.xl)
                
                Spacer()
            }
        }
        .alert("导入失败", isPresented: $backend.showImportError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(backend.importErrorMessage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("角色绑定标签")
    }
    
    /// 关于标签页
    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                // 应用图标
                Image(systemName: "heart.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.pink)
                    .padding(.top, DesignSpacing.xl)
                    .accessibilityLabel("应用图标")
                    .accessibilityHidden(true)

                // 当前角色名称
                Text(petViewBackend.currentCharacter.name)
                    .font(DesignFonts.title)
                    .foregroundColor(DesignColors.textPrimary)

                // 版本信息
                Text("版本 1.0.0")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)

                // 应用描述
                Text("一个可爱的桌面 AI 伴侣")
                    .font(DesignFonts.body)
                    .foregroundColor(DesignColors.textPrimary)
                    .padding(.top, DesignSpacing.xs)

                Spacer()

                // 关闭按钮
                HStack {
                    Spacer()
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .enhancedButtonStyle(isPrimary: false, isDisabled: false)
                    .accessibilityLabel("关闭偏好设置窗口")
                    .accessibilityHint("关闭当前窗口")
                }
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关于标签")
    }
    
    // MARK: - 辅助方法
    
    /// 显示导入GIF对话框
    private func showImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif]
        panel.message = "选择站立GIF文件"
        
        panel.begin { response in
            guard response == .OK, let normalUrl = panel.url else { return }
            
            // 询问角色名称
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
            
            // 询问是否选择动作GIF
            let clickAlert = NSAlert()
            clickAlert.messageText = "选择动作GIF（可选）"
            clickAlert.informativeText = "是否为角色添加点击动作GIF？"
            clickAlert.addButton(withTitle: "选择")
            clickAlert.addButton(withTitle: "跳过")
            
            let clickResponse = clickAlert.runModal()
            
            if clickResponse == .alertFirstButtonReturn {
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
            } else {
                _ = backend.importGIF(normalGif: normalUrl, clickGif: nil, name: characterName)
            }
        }
    }
}


// MARK: - UTType Extension for GIF

extension UTType {
    static var gif: UTType {
        UTType(filenameExtension: "gif") ?? .data
    }
}
