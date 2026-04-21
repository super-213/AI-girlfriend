# 看板娘（macOS 桌面宠物应用）

一个基于 SwiftUI 开发的 macOS 桌面宠物应用，支持 AI 对话、角色切换、音乐搜索、技能注入（agent/skill）和命令执行确认。

## 📋 目录

- [项目概述](#项目概述)
- [核心功能](#核心功能)
- [项目架构](#项目架构)
- [数据流动](#数据流动)
- [目录结构](#目录结构)
- [技术栈](#技术栈)
- [开发与运行](#开发与运行)
- [配置说明](#配置说明)

---

## 项目概述

看板娘是一个悬浮在桌面的 AI 伴侣应用。主宠物窗口提供输入和实时回复，支持 GIF 动画互动；同时提供偏好设置窗口管理模型、角色、布局与技能文件。

应用使用 MVVM 分层，核心逻辑集中在 `PetViewBackend` / `PreferencesViewBackend`，网络请求由 `APIManager` 统一处理。

### 主要特性

- 🎭 **多角色支持**：内置角色 + 自定义角色（最多 3 个）
- 🤖 **AI 对话**：支持智谱清言、通义千问、Ollama（流式输出）
- 🪟 **悬浮对话窗**：`Ctrl + T` 呼出独立无边框聊天窗口
- 🧠 **技能注入**：支持导入 `agent.md` 与多个 `skill.md`
- 🧾 **命令执行管道**：模型可生成命令，客户端二次确认并执行安全命令
- 🎵 **音乐搜索**：识别关键词后打开 Apple Music 搜索
- 💾 **数据持久化**：`@AppStorage + UserDefaults`
- 🎬 **GIF 动画**：支持内置/自定义 GIF，并按帧时长计算动画时长
- ⏰ **自动交互**：随机间隔（270-330 秒）自动播放动作和消息

---

## 核心功能

### 1. 宠物交互
- 点击宠物触发动作 GIF
- 输入文本进行 AI 对话，流式展示响应
- 自动行为循环（随机触发动画与提示）

### 2. 偏好设置
- **风格**：系统提示词、静态提示词
- **模型设置**：Provider、Model、API URL、API Key
- **布局**：输入区/对话区/宠物图像重叠比例
- **技能**：导入或生成 `agent.md`，导入多个 `skill.md`
- **角色绑定**：切换内置角色、导入/删除自定义角色
- **关于**：应用信息与当前角色显示

### 3. 对话窗口
- `Ctrl + T` 打开悬浮对话窗口
- 支持多轮上下文，支持“新建对话”
- 与主窗口共用 `APIManager` 配置（同一套模型参数）

### 4. 命令执行（受控）
- 模型回复中出现命令标记后进入确认弹窗
- 用户确认后本地执行，并将执行结果回注给模型
- 内置白名单前缀：`ls`、`pwd`、`cat`、`zip`、`tar`、`cp`、`mv`、`mkdir`、`rmdir`
- 拦截危险/交互式命令（如 `rm -rf`、`sudo` 等）

### 5. 音乐搜索
- 检测“我想听 / 播放 / 来一首”等关键词
- 自动打开 `music://` 或 Web 版 Apple Music 搜索

---

## 项目架构

### MVVM 架构模式

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│    View     │─────▶│  ViewModel   │─────▶│    Model    │
│  (SwiftUI)  │◀─────│  (Backend)   │◀─────│   (Data)    │
└─────────────┘      └──────────────┘      └─────────────┘
      │                      │                      │
      ▼                      ▼                      ▼
  用户界面              业务逻辑              数据模型/存储
```

### 核心组件关系

```
PetApp (入口)
    │
    ├─▶ PetView (主宠物视图)
    │       └─▶ PetViewBackend
    │               ├─▶ APIManager
    │               ├─▶ MusicPlayerService
    │               ├─▶ GIFDurationCalculator
    │               └─▶ MemoryOptimizer
    │
    ├─▶ PreferencesView (设置窗口)
    │       └─▶ PreferencesViewBackend
    │               ├─▶ 角色导入/删除
    │               ├─▶ staticMessages 持久化
    │               └─▶ agent/skill 文件管理
    │
    └─▶ DialogWindowController (Ctrl+T)
            └─▶ DialogChatView + DialogChatViewModel
                    └─▶ APIManager
```

---

## 数据流动

### 1. 普通对话流程

```
用户输入
    │
    ▼
PetViewBackend.submitInput()
    │
    ├─▶ 命中音乐关键词？
    │   ├─ 是 ─▶ MusicPlayerService.playSong()
    │   └─ 否 ─▶ APIManager.sendStreamRequest()
    │
    ▼
流式回调 onReceive
    │
    ▼
更新 streamedResponse
    │
    ▼
视图实时渲染
```

### 2. Agent/Skill 注入流程

```
systemPrompt
    │
    ├─▶ 读取 agent.md（可选）
    ├─▶ 读取 skill.md 列表（可选）
    ▼
APIManager.buildAugmentedSystemPrompt()
    ▼
合并后 system message 发送给模型
```

### 3. 命令执行闭环

```
模型返回命令标记
    │
    ▼
extractCommand + normalizeCommand
    │
    ▼
显示确认弹窗
    │
    ├─▶ 取消 ─▶ 输出 [完成] 已取消执行命令
    └─▶ 执行 ─▶ runShell() 获取退出码和输出
                     │
                     ▼
                 执行结果回注消息历史
                     │
                     ▼
                 再次请求模型总结
```

### 4. 自动行为流程

```
onAppear / App 激活
    │
    ▼
startAutoActionLoop()
    │
    ▼
随机延迟 270-330 秒
    │
    ▼
performAutoAction()
    ├─▶ 播放动作 GIF
    └─▶ 优先展示 staticMessages，否则角色默认消息
```

---

## 目录结构

```
看板娘/
├── README.md
├── LICENSE
├── 看板娘.xcodeproj/
├── 看板娘/
│   ├── Sources/
│   │   ├── App/
│   │   │   └── PetApp.swift
│   │   ├── Dialog/
│   │   │   ├── DialogWindowController.swift
│   │   │   ├── DialogChatView.swift
│   │   │   └── DialogChatViewModel.swift
│   │   ├── Models/
│   │   │   ├── PreferencesData.swift
│   │   │   ├── PreferencesModels.swift
│   │   │   ├── Provider.swift
│   │   │   └── LayoutConstants.swift
│   │   ├── ViewModels/
│   │   │   ├── PetViewBackend.swift
│   │   │   └── PreferencesViewBackend.swift
│   │   ├── Views/
│   │   │   ├── PetView.swift
│   │   │   └── Preferences/
│   │   │       ├── PreferencesView.swift
│   │   │       ├── Components/
│   │   │       └── PreferencesTabs/
│   │   ├── Services/
│   │   │   ├── APIManager.swift
│   │   │   ├── MusicPlayerService.swift
│   │   │   └── GIFDurationCalculator.swift
│   │   ├── Utils/
│   │   │   ├── MemoryOptimizer.swift
│   │   │   └── gif_library.swift
│   │   └── UI/
│   │       ├── DesignSystem.swift
│   │       └── ViewModifiers.swift
│   └── Resources/
│       ├── Animations/
│       └── Assets.xcassets/
├── 看板娘Tests/
└── 看板娘UITests/
```

---

## 技术栈

### 核心框架
- **SwiftUI**：声明式 UI 与场景管理
- **AppKit**：窗口层级、无边框悬浮窗、系统事件监听
- **Combine**：定时器与响应式状态流

### 第三方库
- **SDWebImage**
- **SDWebImageSwiftUI**

### 数据与存储
- **UserDefaults**
- **@AppStorage**

### 网络通信
- **URLSession**
- **URLSessionDataDelegate**（SSE/流式解析）

---

## 开发与运行

### 环境要求
- macOS（工程部署目标为 **macOS 15.0**）
- 支持 macOS 15 SDK 的 Xcode

### 打开工程
1. 打开 `看板娘.xcodeproj`
2. 选择 Scheme：`看板娘`
3. 直接运行（`⌘R`）

### 命令行构建
```bash
xcodebuild -project 看板娘.xcodeproj -scheme 看板娘 -configuration Debug build
```

### 依赖说明
工程使用本地 Swift Package 引用：

```text
../库/SDWebImageSwiftUI-master
```

请确保该目录存在；若不存在，需要在 Xcode 中重新绑定可用的 SDWebImageSwiftUI 包路径。

---

## 配置说明

### 支持的 AI 服务商

#### 1. 智谱清言（zhipu）
```swift
provider: "zhipu"
apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
aiModel: "glm-4v-flash"
```

#### 2. 通义千问（qwen）
```swift
provider: "qwen"
apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
aiModel: "qwen-plus"
```

#### 3. Ollama（本地）
```swift
provider: "ollama"
apiUrl: "http://localhost:11434/api/chat"
aiModel: "qwen2.5"
apiKey: "ollama" // 本地模式通常不会校验
```

### 自定义角色存储路径

```text
~/Library/Application Support/{BundleID}/CustomAnimations/
```

### Agent/Skill 文件存储位置

```text
~/Library/Application Support/{BundleID}/AgentSkills/
```

### UserDefaults 键名

| 键名 | 类型 | 说明 |
|------|------|------|
| `apiKey` | String | API 密钥 |
| `aiModel` | String | 模型名称 |
| `systemPrompt` | String | 系统提示词 |
| `apiUrl` | String | API 地址 |
| `provider` | String | 服务商标识 |
| `overlapRatio` | Double | 布局重叠比例 |
| `staticMessages` | Data | 静态提示词列表（JSON） |
| `customCharacters` | Data | 自定义角色列表（JSON） |
| `agentFile` | Data | 已导入 agent 文件信息（JSON） |
| `skillFiles` | Data | 已导入 skill 文件列表（JSON） |
| `agentTemplateVersion` | Int | agent 模板版本号 |

---

## 文件职责说明

### App 层
- **PetApp.swift**：应用入口、主窗体样式、偏好设置窗口管理、快捷键注册

### Dialog 层
- **DialogWindowController.swift**：可复用悬浮对话窗口控制器
- **DialogChatView.swift**：对话窗口 UI
- **DialogChatViewModel.swift**：多轮上下文与流式输出状态管理

### ViewModel 层
- **PetViewBackend.swift**：宠物状态、对话主流程、命令执行闭环、自动行为
- **PreferencesViewBackend.swift**：设置管理、角色导入、agent/skill 管理

### Service 层
- **APIManager.swift**：多 Provider 请求构建、流式解析、system prompt 增强注入
- **MusicPlayerService.swift**：歌曲关键词提取与 Apple Music 跳转
- **GIFDurationCalculator.swift**：GIF 实际播放时长计算

### Utils 层
- **MemoryOptimizer.swift**：SDWebImage 缓存与周期性清理
- **gif_library.swift**：角色模型与内置角色库

---

## 开发建议

### 添加新角色
1. 准备站立 GIF（可选动作 GIF）
2. 在偏好设置 → 角色绑定导入
3. 或在 `gif_library.swift` 中扩展内置角色

### 添加新 AI 服务商
1. 在 `APIManager.buildRequest()` 增加 provider 分支
2. 在 `PreferencesViewBackend.handleProviderChange()` 增加默认参数
3. 在 `APIManager.urlSession(_:dataTask:didReceive:)` 增加流式解析逻辑

### 扩展 skill 能力
1. 准备 `agent.md`（可导入或在设置页生成示例）
2. 导入一个或多个 `skill.md`
3. 在提示词里通过技能约束模型的输出与行为

---

## 许可证

本项目仅供学习和个人使用。

---

## 联系方式

如有问题或建议，欢迎提交 Issue。
