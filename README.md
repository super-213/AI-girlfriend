# 桌面宠物应用

一个基于 SwiftUI 开发的 macOS 桌面宠物应用，支持 AI 对话、角色切换、音乐播放等功能。

## 📋 目录

- [项目概述](#项目概述)
- [核心功能](#核心功能)
- [项目架构](#项目架构)
- [数据流动](#数据流动)
- [目录结构](#目录结构)
- [技术栈](#技术栈)
- [配置说明](#配置说明)

---

## 项目概述

这是一个可爱的桌面宠物应用，宠物会悬浮在桌面上，可以与用户进行 AI 对话交互。应用采用 MVVM 架构，代码结构清晰，易于维护和扩展。

### 主要特性

- 🎭 **多角色支持**：内置角色 + 自定义角色（最多3个）
- 🤖 **AI 对话**：支持智谱清言、通义千问、Ollama 等多个 AI 服务商
- 🎵 **音乐播放**：集成 Apple Music 搜索和播放
- 🎨 **自定义样式**：可调整系统提示词、布局重叠度等
- 💾 **数据持久化**：使用 UserDefaults 保存用户设置
- 🎬 **GIF 动画**：支持站立和点击两种动画状态
- ⏰ **自动交互**：定时自动播放动画和显示消息

---

## 核心功能

### 1. 宠物交互
- 点击宠物触发动画
- 输入文本与 AI 对话
- 流式接收 AI 响应
- 定时自动行为（5分钟左右随机触发）

### 2. 偏好设置
- **风格设置**：系统提示词、静态提示词列表
- **模型设置**：AI 服务商、模型名称、API 地址、API 密钥
- **布局设置**：对话框与宠物的重叠比例
- **角色绑定**：切换内置角色、导入自定义角色
- **关于页面**：应用信息和当前角色

### 3. 音乐播放
- 识别"我想听"、"播放"等关键词
- 自动打开 Apple Music 搜索
- 支持歌曲名称提取

---

## 项目架构

### MVVM 架构模式

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│    View     │─────▶│  ViewModel   │─────▶│    Model    │
│  (SwiftUI)  │◀─────│  (Backend)   │◀─────│   (Data)    │
└─────────────┘      └──────────────┘      └─────────────┘
      │                      │                      │
      │                      │                      │
      ▼                      ▼                      ▼
  用户界面              业务逻辑              数据模型
```

### 核心组件关系

```
PetApp (入口)
    │
    ├─▶ PetView (主视图)
    │       └─▶ PetViewBackend (业务逻辑)
    │               ├─▶ APIManager (AI 通信)
    │               ├─▶ MusicPlayerService (音乐播放)
    │               └─▶ GIFDurationCalculator (动画时长)
    │
    └─▶ PreferencesView (设置视图)
            └─▶ PreferencesViewBackend (设置逻辑)
                    ├─▶ StyleSettingsTab
                    ├─▶ ModelSettingsTab
                    ├─▶ LayoutSettingsTab
                    ├─▶ CharacterBindingTab
                    └─▶ AboutTab
```

---

## 数据流动

### 1. 用户输入流程

```
用户输入文本
    │
    ▼
PetView.submitInput()
    │
    ▼
PetViewBackend.submitInput()
    │
    ├─▶ 检测音乐关键词？
    │   ├─ 是 ─▶ MusicPlayerService.playSong()
    │   └─ 否 ─▶ sendRequest()
    │
    ▼
APIManager.sendStreamRequest()
    │
    ├─▶ 构建请求 (buildRequest)
    ├─▶ 发送 HTTP 请求
    └─▶ 流式接收响应
        │
        ▼
    解析 JSON 数据
        │
        ▼
    回调 onReceive
        │
        ▼
    更新 streamedResponse
        │
        ▼
    PetView 显示响应
```

### 2. 设置保存流程

```
用户修改设置
    │
    ▼
PreferencesView 绑定更新
    │
    ▼
PreferencesViewBackend.checkUnsavedChanges()
    │
    ▼
hasUnsavedChanges = true
    │
    ▼
用户点击保存
    │
    ▼
PreferencesViewBackend.saveSettings()
    │
    ├─▶ 保存到 @AppStorage (UserDefaults)
    ├─▶ 发送通知 "SettingsChanged"
    ├─▶ 显示成功消息
    └─▶ 2秒后关闭窗口
```

### 3. 角色切换流程

```
用户选择角色
    │
    ▼
CharacterBindingTab.onChange
    │
    ▼
PreferencesViewBackend.switchCharacter()
    │
    ▼
PetViewBackend.switchToCharacter()
    │
    ├─▶ 更新 currentCharacter
    └─▶ 更新 currentGif
        │
        ▼
    PetView 重新渲染
```

### 4. 自动行为流程

```
应用启动
    │
    ▼
PetViewBackend.onAppear()
    │
    ▼
startAutoActionLoop()
    │
    ▼
scheduleNextAutoAction()
    │
    ▼
延迟 270-330 秒
    │
    ▼
performAutoAction()
    │
    ├─▶ 播放动画 (playNextGif)
    └─▶ 显示随机消息
        │
        ▼
    scheduleNextAutoAction() (循环)
```

---

## 目录结构

```
桌面宠物应用/
│
├── Sources/
│   ├── App/
│   │   └── PetApp.swift                    # 应用入口，窗口配置
│   │
│   ├── Models/                             # 数据模型层
│   │   ├── PreferencesData.swift           # 设置数据结构
│   │   ├── PreferencesModels.swift         # 模型兼容文件（已重构）
│   │   ├── Provider.swift                  # 服务商模型
│   │   └── LayoutConstants.swift           # 布局常量
│   │
│   ├── ViewModels/                         # 业务逻辑层
│   │   ├── PetViewBackend.swift            # 宠物视图业务逻辑
│   │   └── PreferencesViewBackend.swift    # 设置视图业务逻辑
│   │
│   ├── Views/                              # 视图层
│   │   ├── PetView.swift                   # 宠物主视图
│   │   └── Preferences/
│   │       ├── PreferencesView.swift       # 设置主视图
│   │       ├── PreferencesTabs/            # 设置标签页
│   │       │   ├── StyleSettingsTab.swift
│   │       │   ├── ModelSettingsTab.swift
│   │       │   ├── LayoutSettingsTab.swift
│   │       │   ├── CharacterBindingTab.swift
│   │       │   └── AboutTab.swift
│   │       └── Components/                 # 可复用组件
│   │           ├── SystemPromptEditor.swift
│   │           ├── ProviderPicker.swift
│   │           ├── StaticMessagesEditor.swift
│   │           ├── ActionButtons.swift
│   │           ├── SuccessBanner.swift
│   │           ├── CharacterComponents.swift
│   │           ├── LayoutComponents.swift
│   │           └── ModelInputComponents.swift
│   │
│   ├── Services/                           # 服务层
│   │   ├── APIManager.swift                # AI API 通信管理
│   │   ├── MusicPlayerService.swift        # 音乐播放服务
│   │   └── GIFDurationCalculator.swift     # GIF 时长计算
│   │
│   ├── Utils/                              # 工具类
│   │   ├── MemoryOptimizer.swift           # 内存优化
│   │   └── gif_library.swift               # GIF 库（如果存在）
│   │
│   └── UI/                                 # UI 设计系统
│       ├── DesignSystem.swift              # 设计令牌（颜色、间距、动画）
│       └── ViewModifiers.swift             # 可复用视图修饰器
│
├── Resources/                              # 资源文件
│   ├── Animations/                         # GIF 动画文件
│   │   ├── 夏提雅.gif
│   │   ├── 布偶熊动作透明.gif
│   │   └── 布偶熊站立透明.gif
│   └── Assets.xcassets/                    # 应用图标等资源
│
└── Preview Content/                        # 预览资源
```

---

## 技术栈

### 核心框架
- **SwiftUI**：声明式 UI 框架
- **Combine**：响应式编程框架
- **AppKit**：macOS 原生框架

### 第三方库
- **SDWebImage**：GIF 动画加载和缓存
- **SDWebImageSwiftUI**：SwiftUI 集成

### 数据存储
- **UserDefaults**：轻量级键值存储
- **@AppStorage**：SwiftUI 属性包装器

### 网络通信
- **URLSession**：HTTP 请求
- **URLSessionDataDelegate**：流式数据接收

---

## 配置说明

### 支持的 AI 服务商

#### 1. 智谱清言 (ZhiPu)
```swift
provider: "zhipu"
apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
aiModel: "glm-4v-flash"
```

#### 2. 通义千问 (Qwen)
```swift
provider: "qwen"
apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
aiModel: "qwen-plus"
```

#### 3. Ollama (本地)
```swift
provider: "ollama"
apiUrl: "http://localhost:11434/api/chat"
aiModel: "qwen2.5"
apiKey: "ollama" // 不需要真实密钥
```

### 自定义角色存储路径

自定义角色的 GIF 文件存储在：
```
~/Library/Application Support/{BundleID}/CustomAnimations/
```

### UserDefaults 键名

| 键名 | 类型 | 说明 |
|------|------|------|
| `apiKey` | String | API 密钥 |
| `aiModel` | String | AI 模型名称 |
| `systemPrompt` | String | 系统提示词 |
| `apiUrl` | String | API 地址 |
| `provider` | String | 服务商标识 |
| `overlapRatio` | Double | 布局重叠比例 |
| `staticMessages` | Data | 静态提示词列表（JSON） |
| `customCharacters` | Data | 自定义角色列表（JSON） |

---

## 文件职责说明

### App 层
- **PetApp.swift**：应用入口，配置主窗口和偏好设置窗口，设置窗口样式（透明、悬浮、无边框）

### Model 层
- **PreferencesData.swift**：封装所有设置数据，提供默认配置
- **Provider.swift**：服务商数据模型
- **LayoutConstants.swift**：统一的布局常量（间距、尺寸、圆角等）

### ViewModel 层
- **PetViewBackend.swift**：
  - 管理宠物状态（当前角色、GIF、反应状态）
  - 处理用户交互（点击、输入）
  - 控制自动行为定时器
  - 调用 API 服务
  - 内存管理

- **PreferencesViewBackend.swift**：
  - 管理设置界面状态
  - 验证和保存设置
  - 处理角色导入和删除
  - 检测未保存更改
  - 提供商切换逻辑

### View 层
- **PetView.swift**：宠物主界面，包含输入框、对话输出、GIF 动画
- **PreferencesView.swift**：设置主界面，使用 NavigationSplitView 实现侧边栏导航
- **PreferencesTabs/**：各个设置标签页的独立视图
- **Components/**：可复用的 UI 组件

### Service 层
- **APIManager.swift**：
  - 管理 AI API 通信
  - 支持多服务商（智谱、千问、Ollama）
  - 流式响应处理
  - 请求构建和错误处理

- **MusicPlayerService.swift**：
  - 提取歌曲名称
  - 打开 Apple Music 搜索

- **GIFDurationCalculator.swift**：
  - 计算 GIF 总播放时长
  - 读取每帧延迟时间
  - 支持内置和自定义 GIF

### Utils 层
- **MemoryOptimizer.swift**：
  - 配置 SDWebImage 缓存策略
  - 监听内存警告
  - 定期清理缓存

### UI 层
- **DesignSystem.swift**：
  - 颜色系统（主要、次要、语义、状态）
  - 间距系统（xs, sm, md, lg, xl, xxl）
  - 动画配置（持续时间、缓动函数）
  - 字体样式

- **ViewModifiers.swift**：
  - EnhancedTextFieldStyle：文本框焦点和悬停效果
  - EnhancedButtonStyle：按钮交互反馈
  - SmoothScrollStyle：自定义滚动条样式

---

## 开发建议

### 添加新角色
1. 准备站立和动作两个 GIF 文件
2. 在偏好设置 → 角色绑定中导入
3. 或在代码中添加到 `availableCharacters` 数组

### 添加新的 AI 服务商
1. 在 `APIManager.buildRequest()` 中添加新的 case
2. 在 `PreferencesViewBackend.handleProviderChange()` 中添加默认配置
3. 在 `APIManager.urlSession(_:dataTask:didReceive:)` 中添加响应解析逻辑

### 自定义 UI 样式
1. 修改 `DesignSystem.swift` 中的颜色、间距、动画配置
2. 所有视图会自动应用新样式

### 优化内存占用
1. 调整 `MemoryOptimizer` 中的缓存大小限制
2. 修改定期清理的时间间隔
3. 减少 GIF 帧数或分辨率

---

## 许可证

本项目仅供学习和个人使用。

---

## 联系方式

如有问题或建议，欢迎提交 Issue。
