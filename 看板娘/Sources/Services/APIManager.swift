//
//  APIManager.swift
//  桌面宠物应用
//
//  AI API通信管理器，支持流式响应
//

import Foundation
import SwiftUI

// MARK: - API管理器

/// AI API通信管理器
/// 负责与智谱清言和通义千问API进行流式通信
final class APIManager: NSObject, URLSessionDataDelegate {
    
    // MARK: - 配置存储
    
    /// AI模型名称
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    
    /// API密钥
    @AppStorage("apiKey") private var apiKey = "<默认API Key>"
    
    /// 系统提示词
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    
    /// API地址
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    
    /// 服务提供商
    @AppStorage("provider") private var provider = "zhipu"
    
    // MARK: - 会话与任务
    
    /// URL会话实例，用于网络请求
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        let queue = OperationQueue()
        queue.name = "com.xiangban.APIQueue"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    
    /// 当前正在执行的数据任务
    private var task: URLSessionDataTask?
    
    // MARK: - 回调
    
    /// 接收到新内容时的回调闭包
    private var onReceive: ((String) -> Void)?
    
    /// 请求完成时的回调闭包
    private var onComplete: (() -> Void)?

    // MARK: - 外部接口
    
    /// 发送流式请求到AI API
    /// - Parameters:
    ///   - userInput: 用户输入的文本
    ///   - onReceive: 接收到新内容时的回调
    ///   - onComplete: 请求完成时的回调
    func sendStreamRequest(
        userInput: String,
        onReceive: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        cancelPreviousTask()

        guard let request = buildRequest(with: userInput) else {
            #if DEBUG
            print(" 请求构建失败")
            #endif
            onComplete()
            return
        }
        
        // 设置回调
        self.onReceive = onReceive
        self.onComplete = {
            onComplete()
            self.onReceive = nil
            self.onComplete = nil
        }

        // 启动请求
        task = session.dataTask(with: request)
        task?.resume()
    }

    // MARK: - 构建请求体
    
    /// 根据提供商构建API请求
    /// - Parameter userInput: 用户输入的文本
    /// - Returns: 构建好的URLRequest，如果失败则返回nil
    private func buildRequest(with userInput: String) -> URLRequest? {
        // 通用消息体
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userInput]
        ]
        
        // 区分平台，构建 payload
        var payload: [String: Any] = [:]
        
        switch provider.lowercased() {
        case "zhipu":
            payload = [
                "model": aiModel,
                "messages": messages,
                "top_p": 0.7,
                "temperature": 0.9,
                "stream": true,
                "tools": [
                    [
                        "type": "web_search",
                        "web_search": [
                            "enable": true,
                            "search_engine": "search_std"
                        ]
                    ]
                ]
            ]
            
        case "qwen":
            payload = [
                "model": aiModel,
                "input": [
                    "messages": messages
                ],
                "parameters": [
                    "top_p": 0.7,
                    "temperature": 0.9,
                    "stream": true,
                    "type": "json_object"
                ]
            ]
            
        case "ollama":
            payload = [
                "model": aiModel,
                "messages": messages,
                "stream": true,
                "options": [
                    "temperature": 0.9,
                    "top_p": 0.7
                ]
            ]
            
        default:
            #if DEBUG
            print("不支持的 provider: \(provider)")
            #endif
            return nil
        }
        
        // 构造请求
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: apiUrl) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Ollama 不需要 Authorization header
        if provider.lowercased() != "ollama" {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }

    // MARK: - 清理旧任务
    
    /// 取消之前的请求任务
    private func cancelPreviousTask() {
        task?.cancel()
        task = nil
    }

    // MARK: - URL 会话数据委托
    
    /// 接收到数据时的回调
    /// - Parameters:
    ///   - session: URL会话
    ///   - dataTask: 数据任务
    ///   - data: 接收到的数据
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let rawText = String(data: data, encoding: .utf8) else { return }

        #if DEBUG
        print("接收到原始数据：\n\(rawText)")
        #endif

        // Ollama 直接返回 JSON，不使用 SSE 格式
        if provider.lowercased() == "ollama" {
            parseOllamaResponse(rawText)
            return
        }
        
        // 智谱清言和通义千问使用 SSE 格式（data: 前缀）
        let lines = rawText
            .components(separatedBy: "\n")
            .filter { $0.starts(with: "data:") }

        for line in lines {
            let trimmed = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            guard trimmed != "[DONE]" else { continue }

            #if DEBUG
            print("解码前：\(trimmed)")
            #endif

            if let jsonData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                switch provider.lowercased() {
                case "zhipu":
                    if let choices = json["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let content = delta["content"] as? String {
                        DispatchQueue.main.async { [weak self] in
                            self?.onReceive?(content)
                        }
                    }

                case "qwen":
                    if let choices = json["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let content = delta["content"] as? String,
                       !content.isEmpty
                    {
                        DispatchQueue.main.async { [weak self] in
                            self?.onReceive?(content)
                        }
                    }

                default:
                    #if DEBUG
                    print("未知 provider: \(provider)")
                    #endif
                }

            } else {
                #if DEBUG
                print("JSON解析失败: \(trimmed)")
                #endif
            }
        }
    }
    
    /// 解析 Ollama 响应
    /// - Parameter rawText: 原始响应文本
    private func parseOllamaResponse(_ rawText: String) {
        // Ollama 可能在一次回调中返回多个 JSON 对象，用换行符分隔
        let lines = rawText.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                #if DEBUG
                print("Ollama JSON解析失败: \(line)")
                #endif
                continue
            }
            
            // 检查是否有错误
            if let error = json["error"] as? String {
                #if DEBUG
                print("Ollama 错误: \(error)")
                #endif
                continue
            }
            
            // 提取消息内容
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onReceive?(content)
                }
            }
        }
    }
    
    /// 任务完成时的回调
    /// - Parameters:
    ///   - session: URL会话
    ///   - task: URL任务
    ///   - error: 错误信息（如果有）
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                #if DEBUG
                print("任务出错：\(error.localizedDescription)")
                #endif
            }
            self?.onComplete?()
        }
    }
}
