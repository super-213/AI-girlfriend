//
//  PreferencesModels.swift
//  桌面宠物应用
//
//  偏好设置相关的数据模型
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
