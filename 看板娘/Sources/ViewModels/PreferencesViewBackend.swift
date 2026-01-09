//
//  PreferencesViewBackend.swift
//  桌面宠物应用
//
//  偏好设置视图的业务逻辑和状态管理
//

import Foundation
import SwiftUI
import Combine

// MARK: - 偏好设置视图后端

/// 偏好设置视图的后端逻辑控制器
/// 负责管理设置验证、角色绑定和数据持久化
class PreferencesViewBackend: ObservableObject {
    // MARK: - 属性
    
    /// 当前选中的设置分区
    @Published var selectedSection: PreferenceSection? = .style
    
    /// 验证错误字典，键为字段名，值为错误消息
    @Published var validationErrors: [String: String] = [:]
    
    /// 验证状态对象
    @Published var validationState = ValidationState()
    
    /// 是否显示成功消息
    @Published var showSuccessMessage: Bool = false
    
    /// 是否显示错误警告
    @Published var showErrorAlert: Bool = false
    
    /// 错误警告消息内容
    @Published var errorAlertMessage: String = ""
    
    /// 是否有未保存的更改
    @Published var hasUnsavedChanges: Bool = false
    
    /// 静态提示词列表
    @Published var staticMessages: [String] = []
    
    // 角色绑定相关
    
    /// 自定义角色列表
    @Published var customCharacters: [PetCharacter] = []
    
    /// 是否显示导入错误
    @Published var showImportError: Bool = false
    
    /// 导入错误消息
    @Published var importErrorMessage: String = ""
    
    // MARK: - 取消操作的临时存储
    
    /// 临时存储的设置数据（用于取消操作）
    private var tempData: PreferencesData = .default
    
    // MARK: - 依赖项
    
    /// 宠物视图后端的引用
    private let petViewBackend: PetViewBackend
    
    // MARK: - 初始化
    
    /// 初始化偏好设置后端
    /// - Parameter petViewBackend: 宠物视图后端实例
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        loadCustomCharacters()
        loadStaticMessages()
    }
    
    // MARK: - 静态提示词管理
    
    /// 加载静态提示词
    private func loadStaticMessages() {
        if let data = UserDefaults.standard.data(forKey: "staticMessages"),
           let messages = try? JSONDecoder().decode([String].self, from: data) {
            staticMessages = messages
        }
    }
    
    /// 保存静态提示词
    func saveStaticMessages() {
        if let data = try? JSONEncoder().encode(staticMessages) {
            UserDefaults.standard.set(data, forKey: "staticMessages")
        }
    }
    
    // MARK: - 角色绑定方法
    
    /// 加载自定义角色
    private func loadCustomCharacters() {
        if let data = UserDefaults.standard.data(forKey: "customCharacters"),
           let characters = try? JSONDecoder().decode([PetCharacter].self, from: data) {
            customCharacters = characters
        }
    }
    
    /// 保存自定义角色
    /// 保存自定义角色到UserDefaults
    func saveCustomCharacters() {
        if let data = try? JSONEncoder().encode(customCharacters) {
            UserDefaults.standard.set(data, forKey: "customCharacters")
        }
    }
    
    /// 导入GIF文件创建自定义角色
    /// - Parameters:
    ///   - normalGif: 站立状态的GIF文件URL
    ///   - clickGif: 点击动作的GIF文件URL（可选）
    ///   - name: 角色名称
    /// - Returns: 是否导入成功
    func importGIF(normalGif: URL?, clickGif: URL?, name: String) -> Bool {
        guard customCharacters.count < 3 else {
            importErrorMessage = "最多只能保存3个自定义角色"
            showImportError = true
            return false
        }
        
        guard !name.isEmpty else {
            importErrorMessage = "角色名称不能为空"
            showImportError = true
            return false
        }
        
        guard let normalGif = normalGif else {
            importErrorMessage = "必须选择站立GIF"
            showImportError = true
            return false
        }
        
        // 使用Application Support目录存储自定义GIF
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            importErrorMessage = "无法访问应用支持目录"
            showImportError = true
            return false
        }
        
        // 创建应用专属目录
        let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "PetApp")
        let animationsURL = appDirectory.appendingPathComponent("CustomAnimations")
        
        do {
            // 确保目录存在
            if !fileManager.fileExists(atPath: animationsURL.path) {
                try fileManager.createDirectory(at: animationsURL, withIntermediateDirectories: true)
            }
            
            let normalFileName = "\(name)_站立.gif"
            let normalDestURL = animationsURL.appendingPathComponent(normalFileName)
            
            // 如果文件已存在，先删除
            if fileManager.fileExists(atPath: normalDestURL.path) {
                try fileManager.removeItem(at: normalDestURL)
            }
            
            try fileManager.copyItem(at: normalGif, to: normalDestURL)
            
            var clickFileName = normalFileName
            if let clickGif = clickGif {
                clickFileName = "\(name)_动作.gif"
                let clickDestURL = animationsURL.appendingPathComponent(clickFileName)
                
                if fileManager.fileExists(atPath: clickDestURL.path) {
                    try fileManager.removeItem(at: clickDestURL)
                }
                
                try fileManager.copyItem(at: clickGif, to: clickDestURL)
            }
            
            // 创建新角色（保存完整路径）
            let newCharacter = PetCharacter(
                name: name,
                normalGif: normalDestURL.path,
                clickGif: clickFileName == normalFileName ? normalDestURL.path : animationsURL.appendingPathComponent(clickFileName).path,
                autoMessages: ["你好，我是\(name)～"]
            )
            
            customCharacters.append(newCharacter)
            saveCustomCharacters()
            
            return true
        } catch {
            importErrorMessage = "导入失败：\(error.localizedDescription)"
            showImportError = true
            return false
        }
    }
    
    /// 删除指定索引的自定义角色
    /// - Parameter index: 要删除的角色索引
    func deleteCustomCharacter(at index: Int) {
        guard index < customCharacters.count else { return }
        
        let character = customCharacters[index]
        let fileManager = FileManager.default
        
        // 删除GIF文件
        let normalURL = URL(fileURLWithPath: character.normalGif)
        let clickURL = URL(fileURLWithPath: character.clickGif)
        
        try? fileManager.removeItem(at: normalURL)
        if character.normalGif != character.clickGif {
            try? fileManager.removeItem(at: clickURL)
        }
        
        customCharacters.remove(at: index)
        saveCustomCharacters()
    }
}


// MARK: - 偏好设置分区枚举

/// 偏好设置的分区定义
extension PreferencesViewBackend {
    /// 偏好设置分区枚举
    enum PreferenceSection: String, CaseIterable, Identifiable {
        case style = "风格"
        case model = "模型设置"
        case layout = "布局"
        case characterBinding = "角色绑定"
        case about = "关于"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .style: return "person.crop.circle"
            case .model: return "network"
            case .layout: return "rectangle.stack"
            case .characterBinding: return "person.2.crop.square.stack"
            case .about: return "info.circle"
            }
        }
    }
}


// MARK: - 临时值管理

/// 临时值管理扩展
extension PreferencesViewBackend {
    /// 加载当前值到临时存储
    func loadTemporaryValues(
        apiKey: String,
        aiModel: String,
        systemPrompt: String,
        apiUrl: String,
        provider: String,
        overlapRatio: Double
    ) {
        tempData = PreferencesData(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            staticMessages: staticMessages
        )
    }
    
    /// 检查是否有未保存的更改
    func checkUnsavedChanges(
        apiKey: String,
        aiModel: String,
        systemPrompt: String,
        apiUrl: String,
        provider: String,
        overlapRatio: Double
    ) {
        let currentData = PreferencesData(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            staticMessages: staticMessages
        )
        hasUnsavedChanges = currentData != tempData
    }
}


// MARK: - 验证

/// 验证逻辑扩展
extension PreferencesViewBackend {
    /// 验证所有输入字段
    /// - Parameters:
    ///   - apiKey: API密钥
    ///   - apiUrl: API地址
    ///   - aiModel: AI模型名称
    ///   - provider: 服务提供商
    /// - Returns: 是否所有字段都有效
    func validateAllFields(apiKey: String, apiUrl: String, aiModel: String, provider: String = "zhipu") -> Bool {
        validationState.clearErrors()
        
        // Ollama 不需要验证 API Key
        let apiKeyValid = provider == "ollama" ? true : validationState.validateAPIKey(apiKey)
        let apiUrlValid = validationState.validateAPIURL(apiUrl)
        let modelValid = validationState.validateModel(aiModel)
        
        // 更新验证错误字典
        validationErrors.removeAll()
        if provider != "ollama", let error = validationState.apiKeyError {
            validationErrors["apiKey"] = error
        }
        if let error = validationState.apiUrlError {
            validationErrors["apiUrl"] = error
        }
        if let error = validationState.modelError {
            validationErrors["model"] = error
        }
        
        return apiKeyValid && apiUrlValid && modelValid
    }
    
    /// 实时验证API Key
    /// - Parameter apiKey: 要验证的API Key
    func validateAPIKeyRealtime(_ apiKey: String) {
        validationState.validateAPIKey(apiKey)
        if let error = validationState.apiKeyError {
            validationErrors["apiKey"] = error
        } else {
            validationErrors.removeValue(forKey: "apiKey")
        }
    }
    
    /// 实时验证API URL
    /// - Parameter apiUrl: 要验证的API URL
    func validateAPIURLRealtime(_ apiUrl: String) {
        validationState.validateAPIURL(apiUrl)
        if let error = validationState.apiUrlError {
            validationErrors["apiUrl"] = error
        } else {
            validationErrors.removeValue(forKey: "apiUrl")
        }
    }
    
    /// 实时验证模型名称
    /// - Parameter aiModel: 要验证的模型名称
    func validateModelRealtime(_ aiModel: String) {
        validationState.validateModel(aiModel)
        if let error = validationState.modelError {
            validationErrors["model"] = error
        } else {
            validationErrors.removeValue(forKey: "model")
        }
    }
}


// MARK: - 提供商管理

/// 提供商管理扩展
extension PreferencesViewBackend {
    /// 处理提供商切换
    /// - Parameters:
    ///   - newProvider: 新的提供商
    ///   - currentApiUrl: 当前API地址
    ///   - currentModel: 当前模型名称
    /// - Returns: 更新后的API地址和模型名称
    func handleProviderChange(
        newProvider: String,
        currentApiUrl: String,
        currentModel: String
    ) -> (apiUrl: String, model: String) {
        var updatedApiUrl = currentApiUrl
        var updatedModel = currentModel
        
        if newProvider == "zhipu" {
            if currentApiUrl.contains("dashscope") || currentApiUrl.contains("aliyuncs") || currentApiUrl.contains("localhost") || currentApiUrl.isEmpty {
                updatedApiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
            }
            if currentModel.isEmpty || currentModel.contains("qwen") || currentModel.contains("llama") || currentModel.contains("gemma") {
                updatedModel = "glm-4v-flash"
            }
        } else if newProvider == "qwen" {
            if currentApiUrl.contains("bigmodel") || currentApiUrl.contains("localhost") || currentApiUrl.isEmpty {
                updatedApiUrl = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
            }
            if currentModel.isEmpty || currentModel.contains("glm") || currentModel.contains("llama") || currentModel.contains("gemma") {
                updatedModel = "qwen-turbo"
            }
        } else if newProvider == "ollama" {
            if currentApiUrl.contains("bigmodel") || currentApiUrl.contains("dashscope") || currentApiUrl.contains("aliyuncs") || currentApiUrl.isEmpty {
                updatedApiUrl = "http://localhost:11434/api/chat"
            }
            if currentModel.isEmpty || currentModel.contains("glm") || currentModel.contains("qwen-turbo") {
                updatedModel = "qwen2.5"
            }
        }
        
        return (updatedApiUrl, updatedModel)
    }
}


// MARK: - 保存和取消操作

/// 保存和取消操作扩展
extension PreferencesViewBackend {
    /// 保存设置
    /// - Parameters:
    ///   - apiKey: API密钥
    ///   - apiUrl: API地址
    ///   - aiModel: AI模型名称
    ///   - provider: 服务提供商
    ///   - onSuccess: 保存成功回调
    ///   - onDismiss: 关闭窗口回调
    /// - Returns: 是否保存成功
    func saveSettings(
        apiKey: String,
        apiUrl: String,
        aiModel: String,
        provider: String = "zhipu",
        onSuccess: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> Bool {
        // 验证所有字段
        guard validateAllFields(apiKey: apiKey, apiUrl: apiUrl, aiModel: aiModel, provider: provider) else {
            let errors = validationErrors.values.joined(separator: "\n")
            errorAlertMessage = "请修正以下错误：\n\n\(errors)"
            showErrorAlert = true
            return false
        }
        
        // 保存静态提示词
        saveStaticMessages()
        
        // 更新临时值
        onSuccess()
        
        // 发送设置更改通知
        NotificationCenter.default.post(
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // 显示成功消息
        withAnimation(.easeInOut(duration: 0.3)) {
            showSuccessMessage = true
        }
        hasUnsavedChanges = false
        
        // 2秒后隐藏成功消息并关闭窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showSuccessMessage = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
        
        return true
    }
    
    /// 取消更改，恢复到之前的值
    func cancelChanges() {
        validationErrors.removeAll()
        validationState.clearErrors()
        hasUnsavedChanges = false
        staticMessages = tempData.staticMessages
    }
}


// MARK: - 角色管理

/// 角色管理扩展
extension PreferencesViewBackend {
    /// 切换到指定索引的角色
    /// - Parameter index: 角色索引
    func switchCharacter(to index: Int) {
        let newCharacter = availableCharacters[index]
        petViewBackend.switchToCharacter(newCharacter)
    }
    
    /// 获取当前角色在列表中的索引
    /// - Returns: 当前角色的索引
    func getCurrentCharacterIndex() -> Int {
        return availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0
    }
}
