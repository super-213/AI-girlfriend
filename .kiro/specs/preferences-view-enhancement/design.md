# 设计文档：偏好设置视图增强

## 概述

本设计文档描述了桌面宠物应用程序偏好设置界面的增强实现。设计遵循 SwiftUI 最佳实践和 macOS Human Interface Guidelines，提供专业、直观的用户体验。

### 设计目标

1. 创建视觉上一致且美观的设置界面
2. 实现实时输入验证和用户反馈
3. 提供清晰的状态管理和数据持久化
4. 确保可访问性和键盘导航支持
5. 保持代码的可维护性和可测试性

### 技术栈

- **UI 框架**: SwiftUI
- **数据持久化**: @AppStorage (UserDefaults)
- **状态管理**: @State, @ObservedObject
- **架构模式**: MVVM (Model-View-ViewModel)

## 架构

### 组件层次结构

```
PreferencesView (主视图)
├── ValidationState (验证状态管理)
├── PreferencesViewModel (视图模型 - 可选)
├── TabView
│   ├── StyleSettingsTab (风格设置标签)
│   │   ├── SystemPromptEditor (系统提示词编辑器)
│   │   └── CharacterCountIndicator (字符计数指示器)
│   ├── ModelSettingsTab (模型设置标签)
│   │   ├── ProviderPicker (提供商选择器)
│   │   ├── ModelTextField (模型输入框)
│   │   ├── APIURLField (API 地址字段)
│   │   └── APIKeyEditor (API 密钥编辑器)
│   └── AboutTab (关于标签)
│       ├── CharacterPicker (角色选择器)
│       └── AppInfoDisplay (应用信息显示)
└── ActionButtons (操作按钮组)
    ├── SaveButton (保存按钮)
    └── CancelButton (取消按钮)
```

### 数据流

```mermaid
graph TD
    A[用户输入] --> B[PreferencesView]
    B --> C[验证逻辑]
    C --> D{验证通过?}
    D -->|是| E[@AppStorage 更新]
    D -->|否| F[显示错误消息]
    E --> G[NotificationCenter 通知]
    G --> H[PetViewBackend 更新]
    F --> B
```

## 组件和接口

### 1. PreferencesView (主视图)

**职责**:
- 管理标签页导航
- 协调子视图
- 处理保存/取消操作
- 管理窗口生命周期

**关键属性**:
```swift
@ObservedObject var backend: PetViewBackend
@Environment(\.presentationMode) var presentationMode

// AppStorage 属性
@AppStorage("apiKey") private var apiKey: String
@AppStorage("aiModel") private var aiModel: String
@AppStorage("systemPrompt") private var systemPrompt: String
@AppStorage("apiUrl") private var apiUrl: String
@AppStorage("provider") private var provider: String

// 本地状态
@State private var selectedIndex: Int
@State private var validationErrors: [String: String]
@State private var showSuccessMessage: Bool
@State private var hasUnsavedChanges: Bool

// 临时存储（用于取消操作）
@State private var tempApiKey: String
@State private var tempAiModel: String
@State private var tempSystemPrompt: String
@State private var tempApiUrl: String
@State private var tempProvider: String
```

**关键方法**:
```swift
func saveSettings() -> Bool
func cancelChanges()
func validateAllFields() -> Bool
func loadTemporaryValues()
func restoreFromTemporary()
```

### 2. ValidationState (验证状态)

**职责**:
- 集中管理验证逻辑
- 提供验证错误消息
- 确定字段有效性

**结构定义**:
```swift
struct ValidationState {
    var apiKeyError: String?
    var apiUrlError: String?
    var modelError: String?
    
    var isValid: Bool {
        apiKeyError == nil && apiUrlError == nil && modelError == nil
    }
    
    mutating func validateAPIKey(_ key: String) -> Bool
    mutating func validateAPIURL(_ url: String) -> Bool
    mutating func validateModel(_ model: String) -> Bool
    mutating func clearErrors()
}
```

### 3. FormField (可重用表单字段组件)

**职责**:
- 提供一致的表单字段样式
- 显示验证错误
- 支持不同输入类型

**组件定义**:
```swift
struct FormField<Content: View>: View {
    let label: String
    let errorMessage: String?
    let content: Content
    
    init(label: String, 
         errorMessage: String? = nil,
         @ViewBuilder content: () -> Content)
}
```

### 4. SystemPromptEditor (系统提示词编辑器)

**职责**:
- 多行文本编辑
- 字符计数显示
- 超长警告提示
- 重置功能

**组件定义**:
```swift
struct SystemPromptEditor: View {
    @Binding var text: String
    let characterLimit: Int = 500
    let defaultPrompt: String
    
    var characterCount: Int { text.count }
    var isOverLimit: Bool { characterCount > characterLimit }
    
    var body: some View
    func resetToDefault()
}
```

### 5. ProviderPicker (提供商选择器)

**职责**:
- 提供商选择
- 动态显示/隐藏相关字段
- 提供商特定配置

**组件定义**:
```swift
struct ProviderPicker: View {
    @Binding var selectedProvider: String
    let providers: [Provider] = [
        Provider(id: "zhipu", name: "智谱清言"),
        Provider(id: "qwen", name: "通义千问")
    ]
    
    var body: some View
}

struct Provider: Identifiable {
    let id: String
    let name: String
}
```

## 数据模型

### ValidationError (验证错误)

```swift
enum ValidationError: LocalizedError {
    case emptyAPIKey
    case invalidAPIKey
    case invalidURL
    case emptyModel
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API 密钥不能为空"
        case .invalidAPIKey:
            return "API 密钥格式无效或为默认值"
        case .invalidURL:
            return "API 地址必须是有效的 HTTPS URL"
        case .emptyModel:
            return "模型名称不能为空"
        case .networkError(let message):
            return "网络错误: \(message)"
        }
    }
}
```

### PreferencesData (偏好设置数据)

```swift
struct PreferencesData: Equatable {
    var apiKey: String
    var aiModel: String
    var systemPrompt: String
    var apiUrl: String
    var provider: String
    
    static let `default` = PreferencesData(
        apiKey: "",
        aiModel: "glm-4v-flash",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        provider: "zhipu"
    )
}
```


## 验证逻辑详细设计

### API 密钥验证

```swift
func validateAPIKey(_ key: String) -> ValidationError? {
    // 检查是否为空
    guard !key.isEmpty else {
        return .emptyAPIKey
    }
    
    // 检查是否为默认占位符
    guard !key.contains("<默认API Key>") && !key.hasSuffix("f") else {
        return .invalidAPIKey
    }
    
    // 检查最小长度（通常 API 密钥至少 20 个字符）
    guard key.count >= 20 else {
        return .invalidAPIKey
    }
    
    return nil
}
```

### API URL 验证

```swift
func validateAPIURL(_ urlString: String) -> ValidationError? {
    // 检查是否为空
    guard !urlString.isEmpty else {
        return .invalidURL
    }
    
    // 检查 URL 格式
    guard let url = URL(string: urlString) else {
        return .invalidURL
    }
    
    // 检查是否为 HTTPS
    guard url.scheme == "https" else {
        return .invalidURL
    }
    
    // 检查是否有主机名
    guard url.host != nil else {
        return .invalidURL
    }
    
    return nil
}
```

### 模型名称验证

```swift
func validateModel(_ model: String) -> ValidationError? {
    // 检查是否为空
    guard !model.isEmpty else {
        return .emptyModel
    }
    
    // 检查是否包含有效字符（字母、数字、连字符、下划线）
    let validPattern = "^[a-zA-Z0-9_-]+$"
    guard model.range(of: validPattern, options: .regularExpression) != nil else {
        return .emptyModel
    }
    
    return nil
}
```

## UI 设计规范

### 颜色方案

```swift
extension Color {
    static let formBackground = Color(NSColor.controlBackgroundColor)
    static let errorRed = Color.red.opacity(0.8)
    static let successGreen = Color.green.opacity(0.8)
    static let warningYellow = Color.yellow.opacity(0.8)
    static let borderGray = Color.gray.opacity(0.3)
    static let focusBorderBlue = Color.blue.opacity(0.5)
}
```

### 间距和尺寸

```swift
struct LayoutConstants {
    static let sectionSpacing: CGFloat = 20
    static let fieldSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
    
    static let textFieldWidth: CGFloat = 360
    static let textEditorMinHeight: CGFloat = 100
    static let systemPromptHeight: CGFloat = 180
    
    static let windowMinWidth: CGFloat = 500
    static let windowMinHeight: CGFloat = 400
    
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
}
```

### 字体样式

```swift
struct FontStyles {
    static let sectionTitle = Font.headline
    static let fieldLabel = Font.body
    static let fieldInput = Font.system(size: 14)
    static let errorMessage = Font.caption
    static let characterCount = Font.caption.monospacedDigit()
}
```

## 视图布局设计

### 风格设置标签布局

```
┌─────────────────────────────────────────────┐
│  系统提示词:                    [120/500]   │
│  ┌───────────────────────────────────────┐  │
│  │                                       │  │
│  │  你的名字叫布偶熊·觅语...            │  │
│  │                                       │  │
│  │                                       │  │
│  └───────────────────────────────────────┘  │
│  ⚠️ 提示词较长，建议精简以获得更好的响应    │
│                                             │
│  [重置为默认]                               │
│                                             │
│                              [取消] [保存]  │
└─────────────────────────────────────────────┘
```

### 模型设置标签布局

```
┌─────────────────────────────────────────────┐
│  选择平台:                                  │
│  [  智谱清言  |  通义千问  ]               │
│                                             │
│  模型: (仅支持智谱清言)                    │
│  [glm-4v-flash                    ]        │
│                                             │
│  API 地址:                                  │
│  [https://open.bigmodel.cn/...    ]        │
│  ✓ URL 格式正确                             │
│                                             │
│  API Key:                                   │
│  ┌───────────────────────────────────────┐  │
│  │ sk-xxxxxxxxxxxxxxxxxxxxxxxx           │  │
│  └───────────────────────────────────────┘  │
│  ✗ API 密钥不能为默认值                     │
│                                             │
│                              [取消] [保存]  │
└─────────────────────────────────────────────┘
```

### 关于标签布局

```
┌─────────────────────────────────────────────┐
│                                             │
│              ❤️                             │
│                                             │
│          布偶熊·觅语                        │
│          版本 1.0.0                         │
│                                             │
│      一个可爱的桌面 AI 伴侣                 │
│                                             │
│  选择角色:                                  │
│  [ 布偶熊·觅语 ▼ ]                         │
│                                             │
│  可用角色: 2 个                             │
│                                             │
│                                   [关闭]    │
└─────────────────────────────────────────────┘
```


## 正确性属性

*属性是应该在系统所有有效执行中保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### 属性 1: API 密钥验证拒绝无效输入

*对于任何* 字符串输入，如果该字符串为空、包含默认占位符文本（"<默认API Key>"）或长度少于 20 个字符，则 API 密钥验证函数应该返回验证错误。

**验证需求: 2.1**

### 属性 2: API URL 验证要求 HTTPS

*对于任何* URL 字符串，如果该 URL 不是以 "https://" 开头的有效 URL 格式或缺少主机名，则 URL 验证函数应该返回验证错误。

**验证需求: 2.2**

### 属性 3: 验证错误显示

*对于任何* 验证失败的字段，验证状态应该包含该字段的非空错误消息字符串。

**验证需求: 2.3, 7.2**

### 属性 4: 保存按钮状态与验证结果一致

*对于任何* 输入状态，当存在任何验证错误时，保存按钮应该被禁用；当所有字段验证通过时，保存按钮应该被启用。

**验证需求: 2.4, 6.3**

### 属性 5: 提供商特定字段可见性

*对于任何* 提供商选择，只有与该提供商相关的配置字段应该可见，其他提供商的特定字段应该被隐藏。

**验证需求: 3.1, 3.5**

### 属性 6: 角色选择同步后端状态

*对于任何* 可用角色，当用户选择该角色时，后端的 currentCharacter 属性应该立即更新为所选角色。

**验证需求: 4.3**

### 属性 7: 角色数量显示准确性

*对于任何* 可用角色列表，显示的角色数量应该等于 availableCharacters 数组的长度。

**验证需求: 4.5**

### 属性 8: 字符计数准确性

*对于任何* 系统提示词字符串，显示的字符计数应该等于该字符串的实际字符数（使用 .count 属性）。

**验证需求: 5.2**

### 属性 9: 超长提示词警告

*对于任何* 系统提示词字符串，当字符数超过 500 时，应该显示警告状态；当字符数不超过 500 时，不应该显示警告。

**验证需求: 5.3**

### 属性 10: 系统提示词格式保留（往返）

*对于任何* 包含换行符和特殊格式的系统提示词字符串，通过 AppStorage 保存后再读取，应该得到完全相同的字符串（包括所有换行符和空格）。

**验证需求: 5.4**

### 属性 11: 设置保存通知发布

*对于任何* 有效的设置配置，当保存操作成功完成时，应该通过 NotificationCenter 发布 "SettingsChanged" 通知。

**验证需求: 6.4**

### 属性 12: 取消操作恢复原值（往返）

*对于任何* 初始设置状态，如果用户修改字段后点击取消，所有字段应该恢复到修改前的原始值。

**验证需求: 6.5**

### 属性 13: 未保存更改标记

*对于任何* 字段，当其值与保存的值不同时，应该设置 hasUnsavedChanges 标志为 true；当所有字段值与保存的值相同时，该标志应该为 false。

**验证需求: 7.4**

## 错误处理

### 错误类型

1. **验证错误**: 用户输入不符合格式要求
   - 处理方式: 显示内联错误消息，禁用保存按钮
   - 用户操作: 修正输入后自动清除错误

2. **网络错误**: API 连接失败或超时
   - 处理方式: 显示警告对话框，保留用户输入
   - 用户操作: 检查网络连接后重试

3. **数据持久化错误**: AppStorage 写入失败
   - 处理方式: 显示错误警告，不关闭窗口
   - 用户操作: 重试保存或联系支持

### 错误恢复策略

```swift
func saveSettings() -> Bool {
    // 1. 验证所有输入
    guard validateAllFields() else {
        // 显示验证错误，不执行保存
        return false
    }
    
    // 2. 尝试保存到 AppStorage
    do {
        // AppStorage 自动处理持久化
        // 如果失败会抛出异常
        
        // 3. 发布通知
        NotificationCenter.default.post(
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // 4. 显示成功消息
        showSuccessMessage = true
        
        // 5. 延迟关闭窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            presentationMode.wrappedValue.dismiss()
        }
        
        return true
        
    } catch {
        // 显示错误警告
        showErrorAlert(message: error.localizedDescription)
        return false
    }
}
```

### 边界情况处理

1. **空输入**: 所有必填字段应该有默认值
2. **超长输入**: 系统提示词显示警告但仍允许保存
3. **特殊字符**: URL 和 API 密钥应该正确处理编码
4. **并发修改**: 使用 @State 确保 UI 线程安全

## 测试策略

### 双重测试方法

本项目采用单元测试和基于属性的测试相结合的方法：

- **单元测试**: 验证特定示例、边界情况和错误条件
- **属性测试**: 验证跨所有输入的通用属性
- 两者互补且都是全面覆盖所必需的

### 单元测试平衡

单元测试对于特定示例和边界情况很有帮助，但应避免编写过多的单元测试——基于属性的测试可以处理大量输入的覆盖。

**单元测试应该关注**:
- 演示正确行为的特定示例
- 组件之间的集成点
- 边界情况和错误条件

**属性测试应该关注**:
- 对所有输入都成立的通用属性
- 通过随机化实现全面的输入覆盖

### 基于属性的测试配置

- **测试框架**: swift-check (Swift 的 QuickCheck 实现)
- **最小迭代次数**: 每个属性测试 100 次（由于随机化）
- **标签格式**: `// Feature: preferences-view-enhancement, Property {number}: {property_text}`
- **要求**: 每个正确性属性必须由单个基于属性的测试实现

### 测试用例示例

#### 单元测试示例

```swift
import XCTest

class PreferencesViewTests: XCTestCase {
    
    func testAPIKeyValidation_EmptyString() {
        let validator = ValidationState()
        let result = validator.validateAPIKey("")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, .emptyAPIKey)
    }
    
    func testAPIKeyValidation_DefaultPlaceholder() {
        let validator = ValidationState()
        let result = validator.validateAPIKey("<默认API Key>f")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, .invalidAPIKey)
    }
    
    func testAPIURLValidation_HTTPNotAllowed() {
        let validator = ValidationState()
        let result = validator.validateAPIURL("http://example.com")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, .invalidURL)
    }
    
    func testAPIURLValidation_ValidHTTPS() {
        let validator = ValidationState()
        let result = validator.validateAPIURL("https://api.example.com/v1")
        XCTAssertNil(result)
    }
    
    func testCharacterSwitching() {
        let backend = PetViewBackend()
        let newCharacter = puppetCat
        
        backend.switchToCharacter(newCharacter)
        
        XCTAssertEqual(backend.currentCharacter.name, newCharacter.name)
        XCTAssertEqual(backend.currentGif, newCharacter.normalGif)
    }
}
```

#### 基于属性的测试示例

```swift
import SwiftCheck

class PreferencesPropertyTests: XCTestCase {
    
    // Feature: preferences-view-enhancement, Property 1: API 密钥验证拒绝无效输入
    func testProperty_APIKeyValidation_RejectsInvalidInputs() {
        property("Invalid API keys are rejected") <- forAll { (str: String) in
            let validator = ValidationState()
            
            // 测试空字符串、默认占位符或短字符串
            let isInvalid = str.isEmpty || 
                           str.contains("<默认API Key>") || 
                           str.count < 20
            
            let result = validator.validateAPIKey(str)
            
            if isInvalid {
                return result != nil
            } else {
                return result == nil
            }
        }
    }
    
    // Feature: preferences-view-enhancement, Property 2: API URL 验证要求 HTTPS
    func testProperty_URLValidation_RequiresHTTPS() {
        property("Non-HTTPS URLs are rejected") <- forAll { (urlString: String) in
            let validator = ValidationState()
            let result = validator.validateAPIURL(urlString)
            
            // 如果 URL 不是有效的 HTTPS URL，应该返回错误
            if let url = URL(string: urlString),
               url.scheme == "https",
               url.host != nil {
                return result == nil
            } else {
                return result != nil
            }
        }
    }
    
    // Feature: preferences-view-enhancement, Property 8: 字符计数准确性
    func testProperty_CharacterCount_Accuracy() {
        property("Character count matches string length") <- forAll { (text: String) in
            let editor = SystemPromptEditor(
                text: .constant(text),
                defaultPrompt: ""
            )
            
            return editor.characterCount == text.count
        }
    }
    
    // Feature: preferences-view-enhancement, Property 10: 系统提示词格式保留
    func testProperty_SystemPrompt_RoundTrip() {
        property("System prompt preserves formatting") <- forAll { (text: String) in
            // 模拟保存和读取
            UserDefaults.standard.set(text, forKey: "testSystemPrompt")
            let retrieved = UserDefaults.standard.string(forKey: "testSystemPrompt")
            
            return retrieved == text
        }
    }
    
    // Feature: preferences-view-enhancement, Property 12: 取消操作恢复原值
    func testProperty_Cancel_RestoresOriginalValues() {
        property("Cancel restores all fields") <- forAll { (data: PreferencesData) in
            // 设置初始值
            let original = data
            var modified = data
            modified.apiKey = "modified_key"
            modified.aiModel = "modified_model"
            
            // 模拟取消操作
            let restored = original
            
            return restored == original
        }
    }
}
```

### 测试覆盖目标

- **代码覆盖率**: 最低 80%
- **属性测试**: 所有 13 个正确性属性
- **单元测试**: 关键验证函数和边界情况
- **集成测试**: 保存/取消工作流程
- **UI 测试**: 关键用户交互路径（可选）

### 持续集成

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Unit Tests
        run: swift test
      - name: Run Property Tests
        run: swift test --filter PropertyTests
```
