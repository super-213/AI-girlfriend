# 看板娘（macOS 桌面宠物应用）

一个基于 SwiftUI 开发的 macOS 桌面宠物应用，支持 AI 对话、角色切换、音乐搜索、技能注入（agent/skill）、命令执行确认，以及面向外部 Agent 的结构化控制服务。

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

看板娘是一个悬浮在桌面的 AI 伴侣应用。主宠物窗口提供输入和实时回复，支持 GIF 动画互动；同时提供偏好设置窗口管理模型、角色、布局、技能文件与自动化流程。

应用使用 MVVM 分层。界面状态仍由 `PetViewBackend` / `PreferencesViewBackend` 管理，网络请求由 `APIManager` 统一处理；可被机器调用的动作统一收敛到 `PetControlService`，用于后续接入 AppIntents、Shortcuts、URL Scheme、localhost HTTP/WebSocket 或 MCP。

### 主要特性

- 🎭 **多角色支持**：内置角色 + 自定义角色（最多 3 个）
- 🤖 **AI 对话**：支持智谱清言、通义千问、Ollama（流式输出）
- 🪟 **悬浮对话窗**：`Ctrl + T` 呼出独立无边框聊天窗口
- 🧠 **技能注入**：支持导入 `agent.md` 与多个 `skill.md`
- ⏱️ **自动化流程**：在偏好设置中创建常用提示词，按一次、15 分钟、小时、天、周、月、年等频率自动发送给模型
- 🧾 **命令执行管道**：模型可生成命令，客户端二次确认并执行安全命令
- 🧩 **结构化控制 API**：通过 `PetControlService` 提供 sendMessage、switchCharacter、runAutomation、updateSettings、importSkill 等稳定 Swift API
- 📝 **审计日志**：控制服务记录动作来源、请求 ID、执行状态和错误信息，便于追踪外部 Agent 行为
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
- **自动化**：新增、编辑、启停和删除自动化流程，设置名称、提示词和运行频率
- **角色绑定**：切换内置角色、导入/删除自定义角色
- **关于**：应用信息与当前角色显示

### 3. 自动化流程
- 在偏好设置 → 自动化中创建常用提示词流程
- 支持仅运行一次、每15分钟、每小时、每天、每N天（2-7 天）、每周、每月、每年
- 可快速启用/停用或删除流程；空提示词不会进入调度
- 到期后自动把提示词发送给模型，并复用主宠物输出框显示结果
- 已运行的一次性流程会自动停用，重复流程会更新下次运行时间

### 4. 对话窗口
- `Ctrl + T` 打开悬浮对话窗口
- 支持多轮上下文，支持“新建对话”
- 与主窗口共用 `APIManager` 配置（同一套模型参数）

### 5. 命令执行（受控）
- 模型回复中出现命令标记后进入确认弹窗
- 用户确认后本地执行，并将执行结果回注给模型
- 内置白名单前缀：`ls`、`pwd`、`cat`、`zip`、`tar`、`cp`、`mv`、`mkdir`、`rmdir`
- 拦截危险/交互式命令（如 `rm -rf`、`sudo` 等）

### 6. 音乐搜索
- 检测“我想听 / 播放 / 来一首”等关键词
- 自动打开 `music://` 或 Web 版 Apple Music 搜索

### 7. 机器可调用控制服务
- `PetControlService` 是应用内部唯一的稳定控制面
- 支持结构化请求/响应、错误码、请求来源、请求 ID 和 actor 标识
- 当前已覆盖消息发送、角色切换、自动化查询/更新/运行、设置更新和 skill 导入
- UI、未来的 AppIntents/Shortcuts、URL Scheme、localhost HTTP/WebSocket、MCP 都应作为适配层调用该服务

这么做的原因是避免外部大模型或 Agent 依赖 UI 文本、按钮层级、提示词格式或 shell 字符串来“猜”应用行为。稳定 Swift API 能让 OpenClaw 等外部控制方拿到明确的输入输出、错误码和审计记录，也能把权限确认、危险动作拦截和状态判断集中在一个地方维护。

---

## 项目架构

### MVVM 架构模式

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌─────────────┐
│    View     │─────▶│  ViewModel   │─────▶│   Service   │─────▶│ Model/Store │
│  (SwiftUI)  │◀─────│  (Backend)   │◀─────│  (Control)  │◀─────│   (Data)    │
└─────────────┘      └──────────────┘      └─────────────┘      └─────────────┘
      │                      │                      │                    │
      ▼                      ▼                      ▼                    ▼
  用户界面              界面状态              结构化动作            数据模型/存储
```

### 核心组件关系

```
PetApp (入口)
    │
    ├─▶ PetView (主宠物视图)
    │       └─▶ PetViewBackend
    │               ├─▶ PetControlService
    │               ├─▶ APIManager
    │               ├─▶ MusicPlayerService
    │               ├─▶ GIFDurationCalculator
    │               └─▶ MemoryOptimizer
    │
    ├─▶ PreferencesView (设置窗口)
    │       └─▶ PreferencesViewBackend
    │               ├─▶ PetControlService
    │               ├─▶ AutomationStore
    │               ├─▶ 角色导入/删除
    │               ├─▶ staticMessages 持久化
    │               └─▶ agent/skill 文件管理
    │
    └─▶ DialogWindowController (Ctrl+T)
            └─▶ DialogChatView + DialogChatViewModel
                    └─▶ APIManager
```

`PetControlService` 不替代 ViewModel 的界面状态职责，而是把“外部可控制的动作”从 UI 层抽出来。UI 触发、自动化触发和未来的跨进程 Agent 触发都应落到同一套服务方法上，避免同一动作在多个入口重复实现。

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

### 5. 设置页自动化流程

```
偏好设置 → 自动化
    │
    ├─▶ 新增/编辑 AutomationFlow
    ├─▶ 设置提示词与 AutomationFrequency
    ├─▶ AutomationStore 持久化到 UserDefaults
    ▼
PetViewBackend 监听自动化变化
    │
    ├─▶ scheduleNextAutomationAction()
    ├─▶ 到期后筛选 dueAutomations()
    ├─▶ submitAutomationPrompt()
    └─▶ markCompleted() 更新 lastRunAt / nextRunAt
```

自动化流程和随机自动行为是两套机制：随机自动行为只播放动作与静态提示；设置页自动化会按用户配置的频率把提示词提交给模型，并在主宠物输出框展示模型响应。

### 6. 结构化控制流程

```
UI / AppIntents / URL Scheme / localhost HTTP / MCP
    │
    ▼
PetControlService
    ├─▶ 校验结构化输入
    ├─▶ 检查忙碌状态与动作权限
    ├─▶ 调用 PetViewBackend / AutomationStore / UserDefaults
    ├─▶ 返回 DTO 或结构化错误码
    └─▶ 写入审计日志
```

该流程的目标是让外部 Agent 调用 `runAutomation(id:)`、`switchCharacter(index:)`、`importSkill(filePath:)` 这类明确动作，而不是通过模拟点击、读取 UI 文案、解析模型输出或拼接 shell 字符串来控制应用。

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
│   │   │   ├── AutomationModels.swift
│   │   │   ├── Provider.swift
│   │   │   └── LayoutConstants.swift
│   │   ├── Stores/
│   │   │   └── AutomationStore.swift
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
│   │   │   ├── PetControlService.swift
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

### 控制服务审计日志

```text
~/Library/Application Support/{BundleID}/AuditLogs/pet-control.jsonl
```

每一行是一条 JSON 事件，包含 action、requestID、source、actorID、status、message 和 createdAt。该日志用于追踪外部 Agent 或本地 UI 触发了哪些可控动作，以及动作是否成功。

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
| `automationFlows` | Data | 自动化流程列表（JSON） |

---

## 文件职责说明

### App 层
- **PetApp.swift**：应用入口、主窗体样式、偏好设置窗口管理、快捷键注册

### Dialog 层
- **DialogWindowController.swift**：可复用悬浮对话窗口控制器
- **DialogChatView.swift**：对话窗口 UI
- **DialogChatViewModel.swift**：多轮上下文与流式输出状态管理

### ViewModel 层
- **PetViewBackend.swift**：宠物状态、对话主流程、命令执行闭环、自动行为与自动化调度
- **PreferencesViewBackend.swift**：设置分区管理、角色导入、agent/skill 管理

### Service 层
- **APIManager.swift**：多 Provider 请求构建、流式解析、system prompt 增强注入
- **PetControlService.swift**：机器可调用控制面，定义结构化请求/响应、错误码、动作路由和审计日志
- **MusicPlayerService.swift**：歌曲关键词提取与 Apple Music 跳转
- **GIFDurationCalculator.swift**：GIF 实际播放时长计算

### Store 层
- **AutomationStore.swift**：自动化流程的新增、更新、删除、启停、到期查询和 UserDefaults 持久化

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

### 接入外部 Agent
1. 优先把新能力补到 `PetControlService`，定义 Codable 请求、DTO 返回值和错误码
2. 再增加 AppIntents/Shortcuts、URL Scheme、localhost HTTP/WebSocket 或 MCP 适配器
3. 适配器只做鉴权、编解码和传输，不直接改 UI 状态或拼接 shell 命令
4. 高风险动作应在控制服务层集中做权限确认和审计，保证所有入口行为一致

这样可以保持“一个动作只有一个可信实现”。无论动作来自用户点击、快捷指令、OpenClaw 这类外部 Agent，还是未来的本地 HTTP/MCP 工具，最终都会走同一套校验、执行和日志路径。

---

## 许可证

本项目仅供学习和个人使用。

---

## 联系方式

如有问题或建议，欢迎提交 Issue。
