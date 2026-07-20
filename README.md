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

看板娘是一个悬浮在桌面的 AI 伴侣应用。主宠物窗口会按业务状态切换角色素材和状态提示，并在宠物附近按需显示输入、回复气泡、确认卡片与快捷菜单；完整对话和偏好设置继续使用独立窗口。

应用使用 MVVM 分层。`PetStateCoordinator` 统一处理状态优先级、异步 run ID 和短暂效果，`PetViewBackend` 负责把对话、命令、自动化和触发器事件接入状态域；窗口尺寸、穿透、拖动和位置恢复由独立 AppKit 控制层处理。

### 主要特性

- 🎭 **多状态角色**：内置角色 + 自定义角色（最多 3 个），支持 GIF/PNG/JPEG、状态回退和多素材轮换
- 🧭 **状态驱动桌宠**：支持 idle、thinking、talking、working、waitingForConfirmation、success、error、sleeping 等 13 种状态
- 🖱️ **桌面级交互**：透明区域整窗穿透、Alpha 命中拖拽、位置恢复、动态窗口尺寸和屏幕边界约束
- 🤖 **AI 对话**：支持智谱清言、OpenAI-Compatible、Ollama（流式输出）
- 🪟 **悬浮对话窗**：`Ctrl + T` 呼出独立无边框聊天窗口
- 🧠 **技能注入**：支持导入 `agent.md` 与多个 `skill.md`
- ⏱️ **自动化流程**：在偏好设置中创建常用提示词，按一次、15 分钟、小时、天、周、月、年等频率自动发送给模型
- 🧾 **命令执行管道**：模型可生成命令，客户端二次确认并执行安全命令
- 🧩 **结构化控制 API**：通过 `PetControlService` 提供 sendMessage、switchCharacter、runAutomation、updateSettings、importSkill 等稳定 Swift API
- 📝 **审计日志**：控制服务记录动作来源、请求 ID、执行状态和错误信息，便于追踪外部 Agent 行为
- 🎵 **音乐搜索**：识别关键词后打开 Apple Music 搜索
- 💾 **数据持久化**：`@AppStorage + UserDefaults`
- 🧰 **快捷入口**：右键快捷菜单、双击完整对话、Dock + 菜单栏入口
- ⏰ **自动交互**：随机间隔（270-330 秒）自动播放动作和消息

---

## 核心功能

### 1. 宠物交互
- 左键短按播放互动素材，拖动超过 4pt 时移动窗口且不触发点击
- 右键打开快捷菜单，双击打开完整对话
- 悬停显示输入框，AI 回复在限高气泡中流式展示
- 主气泡与完整对话窗口均可停止生成
- 透明像素和窗口空白区域不阻挡后方应用

### 2. 偏好设置
- **风格**：系统提示词、静态提示词
- **模型设置**：Provider、Model、API URL、API Key
- **布局**：休息阈值、气泡时长、命令确认方式和原布局参数
- **技能**：导入或生成 `agent.md`，导入多个 `skill.md`
- **自动化**：新增、编辑、启停和删除自动化流程，设置名称、提示词和运行频率
- **角色绑定**：切换角色，导入 GIF/PNG/JPEG，并为每个业务状态配置多份素材与预览
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
- 模型回复中出现命令标记后进入等待确认状态
- 可在设置中选择宠物附近确认卡片或系统确认弹窗
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
    ├─▶ PetRootView (组件化主宠物视图)
    │       └─▶ PetViewBackend ─▶ PetStateCoordinator
    │               ├─▶ PetControlService
    │               ├─▶ APIManager
    │               ├─▶ PetAssetResolver
    │               ├─▶ TriggerDispatcher / AutomationStore
    │               └─▶ MemoryOptimizer
    │
    ├─▶ PetWindowController / PetWindowHitTestCoordinator
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
│   │   │   ├── PetVisualState.swift
│   │   │   ├── PetAnimationAsset.swift
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
│   │   │   ├── Pet/
│   │   │   └── Preferences/
│   │   │       ├── PreferencesView.swift
│   │   │       ├── Components/
│   │   │       └── PreferencesTabs/
│   │   ├── Services/
│   │   │   ├── APIManager.swift
│   │   │   ├── PetControlService.swift
│   │   │   ├── MusicPlayerService.swift
│   │   │   ├── PetAssetResolver.swift
│   │   │   └── TriggerDispatcher.swift
│   │   ├── Window/
│   │   │   ├── PetWindowController.swift
│   │   │   └── PetWindowHitTestCoordinator.swift
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

只运行单元测试并跳过 UI Tests Runner：

```bash
xcodebuild -project 看板娘.xcodeproj -scheme 看板娘 -destination 'platform=macOS,arch=arm64' -skip-testing:看板娘UITests -only-testing:看板娘Tests test
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

#### 2. OpenAI-Compatible（qwen）
```swift
provider: "qwen"
apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
aiModel: "qwen-plus"
```

`qwen` 是历史保留的 provider ID，实际按 OpenAI-compatible `/v1/chat/completions` 流式接口发送和解析。可用于 DashScope、LM Studio、vLLM、LocalAI 等兼容服务；LM Studio 常用地址为 `http://localhost:1234/v1/chat/completions`。

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
| `petSleepMinutes` | Double | 空闲多久进入休息，0 表示关闭 |
| `commandConfirmationStyle` | String | `nearPet` 或 `systemAlert` |
| `bubbleAutoHideDuration` | Double | 回复气泡自动收起秒数 |
| `petWindowPlacement.v2` | Data | 显示器标识和相对窗口位置 |
| `selectedPetCharacterID` | String | 当前角色稳定 ID |
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
- **PetViewBackend.swift**：对话、命令、自动化和触发器到状态事件的业务接线
- **PetVisualState.swift**：状态、事件、优先级、run ID 防乱序和短暂效果回落
- **PetWindowController.swift**：动态尺寸、底部锚定、拖动位置和多显示器恢复
- **PreferencesViewBackend.swift**：设置分区管理、角色导入、agent/skill 管理

### Service 层
- **APIManager.swift**：多 Provider 请求构建、流式解析、system prompt 增强注入
- **PetControlService.swift**：机器可调用控制面，定义结构化请求/响应、错误码、动作路由和审计日志
- **MusicPlayerService.swift**：歌曲关键词提取与 Apple Music 跳转
- **GIFDurationCalculator.swift**：GIF 实际播放时长计算
- **PetAssetResolver.swift**：状态素材轮换、交互素材和统一回退链

### Store 层
- **AutomationStore.swift**：自动化流程的新增、更新、删除、启停、到期查询和 UserDefaults 持久化

### Utils 层
- **MemoryOptimizer.swift**：SDWebImage 缓存与周期性清理
- **gif_library.swift**：内置角色库

---

## 开发建议

### 添加新角色
1. 准备待命素材（GIF、PNG 或 JPEG）以及可选互动素材
2. 在偏好设置 → 角色绑定导入，并确认拥有素材使用权
3. 点击“状态素材”为不同状态添加一份或多份素材；缺失状态会按统一回退链使用待命素材
4. 旧版 `normalGif/clickGif` 自定义角色按已确认策略不自动迁移，需要重新导入

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
