import Foundation
import SwiftUI
import Combine

class PreferencesViewBackend: ObservableObject {
    // MARK: - Published Properties
    
    @Published var selectedSection: PreferenceSection? = .style
    @Published var validationErrors: [String: String] = [:]
    @Published var validationState = ValidationState()
    @Published var showSuccessMessage: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var errorAlertMessage: String = ""
    @Published var hasUnsavedChanges: Bool = false
    
    // MARK: - Temporary Storage for Cancel Operation
    
    var tempApiKey: String = ""
    var tempAiModel: String = ""
    var tempSystemPrompt: String = ""
    var tempApiUrl: String = ""
    var tempProvider: String = ""
    var tempOverlapRatio: Double = 0.3
    
    // MARK: - Dependencies
    
    private let petViewBackend: PetViewBackend
    
    // MARK: - Initialization
    
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
    }
}


// MARK: - Preference Section Enum

extension PreferencesViewBackend {
    enum PreferenceSection: String, CaseIterable, Identifiable {
        case style = "风格"
        case model = "模型设置"
        case layout = "布局"
        case about = "关于"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .style: return "person.crop.circle"
            case .model: return "network"
            case .layout: return "rectangle.stack"
            case .about: return "info.circle"
            }
        }
    }
}


// MARK: - Temporary Values Management

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
        tempApiKey = apiKey
        tempAiModel = aiModel
        tempSystemPrompt = systemPrompt
        tempApiUrl = apiUrl
        tempProvider = provider
        tempOverlapRatio = overlapRatio
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
        hasUnsavedChanges = apiKey != tempApiKey ||
                           aiModel != tempAiModel ||
                           systemPrompt != tempSystemPrompt ||
                           apiUrl != tempApiUrl ||
                           provider != tempProvider ||
                           overlapRatio != tempOverlapRatio
    }
}


// MARK: - Validation

extension PreferencesViewBackend {
    /// 验证所有输入字段
    func validateAllFields(apiKey: String, apiUrl: String, aiModel: String) -> Bool {
        validationState.clearErrors()
        
        let apiKeyValid = validationState.validateAPIKey(apiKey)
        let apiUrlValid = validationState.validateAPIURL(apiUrl)
        let modelValid = validationState.validateModel(aiModel)
        
        // 更新验证错误字典
        validationErrors.removeAll()
        if let error = validationState.apiKeyError {
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
    
    /// 实时验证 API Key
    func validateAPIKeyRealtime(_ apiKey: String) {
        validationState.validateAPIKey(apiKey)
        if let error = validationState.apiKeyError {
            validationErrors["apiKey"] = error
        } else {
            validationErrors.removeValue(forKey: "apiKey")
        }
    }
    
    /// 实时验证 API URL
    func validateAPIURLRealtime(_ apiUrl: String) {
        validationState.validateAPIURL(apiUrl)
        if let error = validationState.apiUrlError {
            validationErrors["apiUrl"] = error
        } else {
            validationErrors.removeValue(forKey: "apiUrl")
        }
    }
    
    /// 实时验证模型
    func validateModelRealtime(_ aiModel: String) {
        validationState.validateModel(aiModel)
        if let error = validationState.modelError {
            validationErrors["model"] = error
        } else {
            validationErrors.removeValue(forKey: "model")
        }
    }
}


// MARK: - Provider Management

extension PreferencesViewBackend {
    /// 处理提供商切换
    func handleProviderChange(
        newProvider: String,
        currentApiUrl: String,
        currentModel: String
    ) -> (apiUrl: String, model: String) {
        var updatedApiUrl = currentApiUrl
        var updatedModel = currentModel
        
        if newProvider == "zhipu" {
            if currentApiUrl.contains("dashscope") || currentApiUrl.contains("aliyuncs") || currentApiUrl.isEmpty {
                updatedApiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
            }
            if currentModel.isEmpty || currentModel.contains("qwen") {
                updatedModel = "glm-4v-flash"
            }
        } else if newProvider == "qwen" {
            if currentApiUrl.contains("bigmodel") || currentApiUrl.isEmpty {
                updatedApiUrl = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
            }
            if currentModel.isEmpty || currentModel.contains("glm") {
                updatedModel = "qwen-turbo"
            }
        }
        
        return (updatedApiUrl, updatedModel)
    }
}


// MARK: - Save and Cancel Operations

extension PreferencesViewBackend {
    /// 保存设置
    func saveSettings(
        apiKey: String,
        apiUrl: String,
        aiModel: String,
        onSuccess: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> Bool {
        // 验证所有字段
        guard validateAllFields(apiKey: apiKey, apiUrl: apiUrl, aiModel: aiModel) else {
            let errors = validationErrors.values.joined(separator: "\n")
            errorAlertMessage = "请修正以下错误：\n\n\(errors)"
            showErrorAlert = true
            return false
        }
        
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
    
    /// 取消更改
    func cancelChanges() {
        validationErrors.removeAll()
        validationState.clearErrors()
        hasUnsavedChanges = false
    }
}


// MARK: - Character Management

extension PreferencesViewBackend {
    /// 切换角色
    func switchCharacter(to index: Int) {
        let newCharacter = availableCharacters[index]
        petViewBackend.switchToCharacter(newCharacter)
    }
    
    /// 获取当前角色索引
    func getCurrentCharacterIndex() -> Int {
        return availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0
    }
}
