//
//  PreferencesData.swift
//  桌面宠物应用
//
//  偏好设置数据模型
//

import Foundation

/// 偏好设置数据结构体，封装所有设置数据
struct PreferencesData: Equatable {
    var apiKey: String
    var aiModel: String
    var systemPrompt: String
    var apiUrl: String
    var provider: String
    var overlapRatio: Double
    var staticMessages: [String]
    
    static let `default` = PreferencesData(
        apiKey: "",
        aiModel: "glm-4v-flash",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        provider: "zhipu",
        overlapRatio: 0.3,
        staticMessages: []
    )
    
    /// Ollama 默认配置
    static let ollamaDefault = PreferencesData(
        apiKey: "ollama",
        aiModel: "qwen2.5",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "http://localhost:11434/api/chat",
        provider: "ollama",
        overlapRatio: 0.3,
        staticMessages: []
    )
}
