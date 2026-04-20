//
//  PreferencesModels.swift
//  桌面宠物应用
//
//  偏好设置相关的数据模型（已重构）
//  注意：此文件中的大部分内容已被拆分到独立文件中
//  保留此文件以维持向后兼容性
//

import Foundation

// MARK: - Agent/Skill 文件存储键

enum AgentSkillStorageKeys {
    static let agentFile = "agentFile"
    static let skillFiles = "skillFiles"
    static let agentTemplateVersion = "agentTemplateVersion"
}

// MARK: - Agent/Skill 文件模型

/// 单个 agent.md 文件记录
struct AgentFile: Codable, Equatable {
    var name: String
    var path: String
    var updatedAt: Date
}

/// skill.md 文件记录（可多个）
struct SkillFile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var addedAt: Date
}

// 所有模型和组件已被拆分到以下文件：
// - Sources/Models/PreferencesData.swift
// - Sources/Models/LayoutConstants.swift
// - Sources/Models/Provider.swift
// - Sources/Views/Preferences/Components/SystemPromptEditor.swift
// - Sources/Views/Preferences/Components/ProviderPicker.swift
// - Sources/Views/Preferences/Components/ActionButtons.swift
// - Sources/Views/Preferences/Components/SuccessBanner.swift
// - Sources/Views/Preferences/Components/StaticMessagesEditor.swift
// - Sources/Views/Preferences/Components/LayoutComponents.swift
