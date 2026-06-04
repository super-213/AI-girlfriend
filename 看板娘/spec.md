# 看板娘 - 规格说明书

macOS 桌面宠物应用规格说明书｜基于 Spec-Driven Development｜版本：v1.0


---

## 文档元信息

| 字段 | 内容 |
|------|------|
| **文档名称** | 看板娘-macOS桌面宠物-规格说明书 |
| **文档ID** | SPEC-KANBAN-20260512-001 |
| **负责人** | 姜智浩 |
| **优先级** | P1 |
| **预期上线** | 已发布 |
| **最后更新** | 2026-05-15 |
| **文档状态** |  已定稿 |
| **关联需求** | 桌面宠物应用开发 |
| **技术栈** | SwiftUI / AppKit / Combine / URLSession |

---

## Problem Statement

### 1.1 当前现状（As-Is）

- macOS 用户在长时间使用电脑工作时，缺乏桌面陪伴类应用
- 现有桌面宠物应用功能单一，缺乏 AI 对话能力和自动化能力
- 用户需要在不同窗口间切换才能与 AI 助手交互，打断工作流
- 外部 Agent 或自动化工具难以控制桌面应用，缺乏稳定的结构化 API

### 1.2 核心问题（Problem）

在日常办公场景下，macOS 用户无法拥有一个既能提供陪伴感又能进行 AI 对话的桌面宠物，导致工作体验单调、AI 交互成本高。

### 1.3 影响范围（Scope）

| 维度 | 内容 |
|------|------|
| **涉及系统** | macOS 桌面宠物应用（看板娘） |
| **目标用户** | macOS 桌面用户、AI 助手使用者、自动化爱好者 |
| **业务场景** | 日常办公陪伴、AI 对话、自动化任务执行、桌面交互 |
| **平台范围** | macOS 15.0+ |
| **部署方式** | 本地应用，支持云端 AI 和本地模型（Ollama） |

---

## Success Metrics

### 2.1 核心指标（Must-Have）

| 指标类型 | 指标名称 | 目标值 | 测量方式 |
|----------|----------|--------|----------|
| **功能** | AI 对话成功率 | ≥ 95% | 流式响应正常完成率 |
| **功能** | 自动化任务准时执行 | ≥ 99% | 调度系统日志统计 |
| **体验** | 宠物点击响应延迟 | < 100ms | 动画播放延迟测量 |
| **体验** | 悬浮对话窗快捷键响应 | < 200ms | Ctrl+T 唤起延迟 |
| **安全** | 危险命令拦截率 | 100% | 命令执行白名单检查 |
| **稳定性** | 应用崩溃率 | < 0.1% | 系统崩溃日志统计 |

### 2.2 辅助指标（Nice-to-Have）

- 用户自定义角色导入成功率：≥ 90%
- 技能文件（agent.md/skill.md）导入成功率：≥ 95%
- 审计日志完整性：100%

### 2.3 验收门槛（Go/No-Go）

- [x] AI 流式对话功能正常（支持智谱清言、OpenAI-Compatible、Ollama）
- [x] 自动化流程调度正常（支持 8 种频率）
- [x] 命令执行确认机制完整
- [x] 音乐搜索跳转功能正常
- [x] PetControlService 结构化 API 可用

---

## User Stories（用户故事）

### 3.1 核心用户故事（Core）

#### US-001｜AI 对话

> 作为 **桌面用户**，
> 我希望 **在桌面上直接与 AI 进行对话**，
> 以便 **无需切换窗口即可获得 AI 协助**。

**验收关联**：AC-001, AC-002

#### US-002｜角色切换

> 作为 **桌面用户**，
> 我希望 **切换不同的宠物角色**，
> 以便 **获得不同的陪伴体验和视觉风格**。

**验收关联**：AC-003, AC-004

#### US-003｜自动化任务

> 作为 **自动化爱好者**，
> 我希望 **设置定时自动执行的提示词任务**，
> 以便 **在特定时间自动获取 AI 回复或执行操作**。

**验收关联**：AC-005, AC-006

#### US-004｜命令执行

> 作为 **开发者用户**，
> 我希望 **让 AI 生成并执行安全的 shell 命令**，
> 以便 **通过对话完成简单的系统操作**。

**验收关联**：AC-007, AC-008

#### US-005｜音乐搜索

> 作为 **音乐爱好者**，
> 我希望 **通过对话让宠物帮我搜索并播放音乐**，
> 以便 **在工作时轻松享受音乐**。

**验收关联**：AC-009

#### US-006｜技能注入

> 作为 **高级用户**，
> 我希望 **导入 agent.md 和 skill.md 文件来扩展宠物的能力**，
> 以便 **定制 AI 的行为和知识**。

**验收关联**：AC-010

### 3.2 边缘场景故事（Edge）

#### US-E01｜悬浮对话窗

> 作为 **多任务用户**，
> 我希望 **通过快捷键快速呼出独立的对话窗口**，
> 以便 **在不打扰主窗口的情况下进行对话**。

**验收关联**：AC-011

#### US-E02｜外部 Agent 控制

> 作为 **自动化工具开发者**，
> 我希望 **通过 PetControlService 的结构化 API 控制应用**，
> 以便 **让外部 Agent 或脚本能够可靠地操作宠物**。

**验收关联**：AC-012

---

## Acceptance Criteria（验收标准）

### 4.1 功能验收（Functional）

#### AC-001｜AI 流式对话

> **Given** 用户已配置 API 密钥和模型
> **When** 在输入框输入文本并提交
> **Then** AI 响应以流式方式逐字显示，显示"思考中"状态

#### AC-002｜多 Provider 支持

> **Given** 用户选择不同的 AI 服务商
> **When** 切换 Provider（zhipu/qwen/ollama）
> **Then** API 地址、请求格式、解析逻辑自动适配

#### AC-003｜内置角色切换

> **Given** 用户点击宠物或打开偏好设置
> **When** 选择不同角色
> **Then** 宠物 GIF 和自动消息切换为对应角色

#### AC-004｜自定义角色导入

> **Given** 用户准备了自定义 GIF 文件
> **When** 在偏好设置中导入角色
> **Then** 角色出现在可选列表，最多支持 3 个自定义角色

#### AC-005｜自动化流程创建

> **Given** 用户进入偏好设置 → 自动化
> **When** 创建新流程并设置提示词和频率
> **Then** 流程被保存并在指定时间自动执行

#### AC-006｜自动化调度频率

> **Given** 自动化流程已启用
> **When** 到达执行时间
> **Then** 按配置频率（仅一次/每15分钟/每小时/每天/每N天/每周/每月/每年）执行

#### AC-007｜命令确认机制

> **Given** AI 响应包含命令标记
> **When** 检测到待执行命令
> **Then** 弹出确认窗口，用户确认后执行

#### AC-008｜危险命令拦截

> **Given** AI 生成的命令包含危险操作
> **When** 命令匹配黑名单（rm -rf、sudo 等）
> **Then** 拒绝执行并提示风险

#### AC-009｜音乐关键词识别

> **Given** 用户输入包含"播放/听歌/来一首"等关键词
> **When** 识别到音乐意图
> **Then** 自动打开 Apple Music 搜索对应歌曲

#### AC-010｜技能文件导入

> **Given** 用户准备了 agent.md 或 skill.md 文件
> **When** 在偏好设置中导入
> **Then** 文件内容被合并到系统提示词中发送给模型

### 4.2 体验验收（UX）

#### AC-011｜悬浮对话窗

> **Given** 应用正在运行
> **When** 用户按下 Ctrl+T
> **Then** 弹出独立的悬浮对话窗口，支持多轮对话

#### AC-012｜窗口拖动

> **Given** 用户点击宠物非交互区域
> **When** 拖动鼠标
> **Then** 窗口跟随移动，不干扰输入框交互

### 4.3 安全验收（Security）

#### AC-013｜审计日志

> **Given** PetControlService 执行任意动作
> **When** 动作完成
> **Then** 审计日志记录：动作类型、请求ID、来源、执行状态、时间戳

---

## Non-Goals（明确不做）

### 5.1 本期明确不包含（Out of Scope）

- [ ] 不支持 Windows / Linux 平台（仅 macOS）
- [ ] 不支持多宠物同时显示
- [ ] 不提供云端同步功能
- [ ] 不支持语音输入/输出
- [ ] 不集成 App Store 分发（本地构建）
- [ ] 不提供宠物动作编辑器（仅支持 GIF 导入）

### 5.2 后续演进规划（Roadmap）

| 版本 | 核心能力 | 业务价值 | 预估时间 |
|------|----------|----------|----------|
| V2.0 | AppIntents / Shortcuts 集成 | 支持 Siri 和快捷指令控制 | 2026 Q3 |
| V2.5 | URL Scheme 支持 | 支持外部应用调用 | 2026 Q4 |
| V3.0 | localhost HTTP/WebSocket API | 支持本地服务调用 | 2027 Q1 |
| V3.5 | MCP 协议支持 | 支持标准 Agent 协议 | 2027 Q2 |

---

## Constraints（约束条件）

### 6.1 技术约束（Technical）

- **平台**：仅支持 macOS 15.0+，使用 SwiftUI + AppKit
- **架构**：MVVM 分层，状态由 ViewModel 管理
- **存储**：UserDefaults + @AppStorage，无数据库依赖
- **网络**：URLSession 原生网络库，支持 SSE 流式响应
- **依赖**：SDWebImageSwiftUI（本地包引用）

### 6.2 业务约束（Business）

- **角色限制**：最多支持 3 个自定义角色
- **自动化**：每 N 天频率限制在 2-7 天范围内
- **命令执行**：仅支持白名单前缀命令（ls、pwd、cat、zip、tar、cp、mv、mkdir、rmdir）

### 6.3 安全约束（Security）

- **API Key**：明文存储于 UserDefaults（后续版本应迁移至 Keychain）
- **命令执行**：所有命令需用户二次确认
- **危险拦截**：自动拦截 rm -rf、sudo 等危险命令

---

## 附录 A：架构方案摘要

### A.1 核心架构

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌─────────────┐
│    View     │─────▶│  ViewModel   │─────▶│   Service   │─────▶│ Model/Store │
│  (SwiftUI)  │◀─────│  (Backend)   │◀─────│  (Control)  │◀─────│   (Data)    │
└─────────────┘      └──────────────┘      └─────────────┘      └─────────────┘
```

### A.2 核心组件关系

```
PetApp (入口)
    │
    ├─▶ PetView (主宠物视图)
    │       └─▶ PetViewBackend
    │               ├─▶ PetControlService
    │               ├─▶ APIManager
    │               ├─▶ MusicPlayerService
    │               └─▶ GIFDurationCalculator
    │
    ├─▶ PreferencesView (设置窗口)
    │       └─▶ PreferencesViewBackend
    │               ├─▶ PetControlService
    │               ├─▶ AutomationStore
    │               └─▶ 角色导入/删除
    │
    └─▶ DialogWindowController (Ctrl+T)
            └─▶ DialogChatView + DialogChatViewModel
```

### A.3 关键设计决策

| 决策点 | 方案选择 | 理由 |
|--------|----------|------|
| 状态管理 | ObservableObject + @Published | SwiftUI 原生响应式 |
| 网络请求 | URLSession + SSE | 原生支持流式响应 |
| 数据持久化 | UserDefaults + @AppStorage | 轻量级，无需数据库 |
| 控制层 | PetControlService 独立服务层 | 支持外部 Agent 调用 |

---

## 附录 B：数据模型摘要

### B.1 核心模型

| 模型 | 文件 | 说明 |
|------|------|------|
| `PetCharacter` | gif_library.swift | 角色模型：name, normalGif, clickGif, autoMessages |
| `AutomationFlow` | AutomationModels.swift | 自动化流程：id, title, prompt, frequency, isEnabled |
| `AutomationFrequency` | AutomationModels.swift | 频率枚举：runOnce, hourly, daily, weekly, monthly, yearly 等 |
| `AgentFile` | PreferencesModels.swift | Agent 文件记录：name, path, updatedAt |
| `SkillFile` | PreferencesModels.swift | Skill 文件记录：id, name, path, addedAt |

### B.2 PetControlService 数据模型

| 模型 | 说明 |
|------|------|
| `SendMessageRequest/Result` | 发送消息请求/结果 |
| `SwitchCharacterRequest/CharacterDTO` | 切换角色请求/角色数据 |
| `AutomationDTO` | 自动化流程数据传输对象 |
| `SettingsPatch/Snapshot` | 设置更新/快照 |
| `SkillDTO` | 技能文件数据传输对象 |
| `PetControlError` | 结构化错误：invalidInput, notFound, busy, permissionDenied 等 |

---

## 附录 C：API 支持的 Provider 配置

### C.1 智谱清言（zhipu）

```swift
provider: "zhipu"
apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
aiModel: "glm-4v-flash"
```

### C.2 OpenAI-Compatible（qwen）

```swift
provider: "qwen"
apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
aiModel: "qwen-plus"
```

### C.3 Ollama（本地）

```swift
provider: "ollama"
apiUrl: "http://localhost:11434/api/chat"
aiModel: "qwen2.5"
```

---

## 附录 D：存储路径说明

| 数据类型 | 存储路径 |
|----------|----------|
| 自定义角色 | `~/Library/Application Support/{BundleID}/CustomAnimations/` |
| Agent/Skill 文件 | `~/Library/Application Support/{BundleID}/AgentSkills/` |
| 审计日志 | `~/Library/Application Support/{BundleID}/AuditLogs/pet-control.jsonl` |

---

## 附录 E：UserDefaults 键名

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
| `automationFlows` | Data | 自动化流程列表（JSON） |

---

## 变更历史（Changelog）

| 版本 | 日期 | 变更类型 | 变更内容摘要 |
|------|------|----------|--------------|
| v1.0 | 2026-05-12 | 初稿 | 根据 README 和代码创建规格说明书 |
| v1.1 | 2026-05-15 | 定稿 | 按要求完成构建 |


---

## 评审与验收流程

### 评审 Checklist

- [x] **功能覆盖**：所有核心功能均有对应的 User Story 和 AC
- [x] **架构合理**：MVVM 分层清晰，职责明确
- [x] **安全考虑**：命令执行有确认机制，危险命令有拦截
- [x] **扩展性**：PetControlService 为外部 Agent 调用预留接口
- [x] **文档完整**：数据模型、存储路径、配置项均有说明
