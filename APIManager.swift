import Foundation
import SwiftUI

final class APIManager: NSObject, URLSessionDataDelegate {
    
    // MARK: - 配置存储
    
    @AppStorage("ai_model") private var aiModel = "glm-4v-flash"
    @AppStorage("apiKey") private var apiKey = "<默认API Key>"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
<<<<<<< HEAD
    @AppStorage("provider") private var provider = "zhipu"
    
    // MARK: - 会话与任务
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        let queue = OperationQueue()
        queue.name = "com.xiangban.APIQueue"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    
    private var task: URLSessionDataTask?
    
    // MARK: - 回调
    
    private var onReceive: ((String) -> Void)?
    private var onComplete: (() -> Void)?
=======

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        // 显式创建共享的 delegateQueue，避免系统创建无数新线程
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.name = "com.xiangban.APIQueue"
        return URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
    }()
    private var task: URLSessionDataTask?
    
    private var onReceive: ((String) -> Void)?
    private var onComplete: (() -> Void)?

    /// 发送流式请求
    func sendStreamRequest(userInput: String,
                           onReceive: @escaping (String) -> Void,
                           onComplete: @escaping () -> Void) {
        
        // 取消之前任务
        task?.cancel()
        task = nil

        // 构建请求体
        let requestBody: [String: Any] = [
            "model": aiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userInput]
            ],
            "top_p": 0.7,
            "temperature": 0.9,
            "stream": true,
            "tools":[
                [
                    "type": "web_search",
                    "web_search": [
                        "enable": true,
                        "search_engine": "search_std"
                    ]
                ]
            ]
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            onComplete()
            return
        }

        var request = URLRequest(url: URL(string: apiUrl)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        // 存储回调
        self.onReceive = onReceive
        self.onComplete = {
            onComplete()
            self.onReceive = nil
            self.onComplete = nil
        }

        // 使用持久化 session，避免重复创建
        task = session.dataTask(with: request)
        task?.resume()
    }

    // MARK: - URLSessionDataDelegate
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682

    // MARK: - 外部接口
    
    func sendStreamRequest(
        userInput: String,
        onReceive: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        cancelPreviousTask()

        guard let request = buildRequest(with: userInput) else {
            print(" 请求构建失败")
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
            
        default:
            print("不支持的 provider: \(provider)")
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        return request
    }

    // MARK: - 清理旧任务
    
    private func cancelPreviousTask() {
        task?.cancel()
        task = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
<<<<<<< HEAD
        guard let rawText = String(data: data, encoding: .utf8) else { return }

        print("接收到原始数据：\n\(rawText)")

        let lines = rawText
            .components(separatedBy: "\n")
            .filter { $0.starts(with: "data:") }

        for line in lines {
            let trimmed = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            guard trimmed != "[DONE]" else { continue }

            print("解码前：\(trimmed)")

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
                    /*
                     使用阿里云 OpenAI 兼容接口时，Qwen 模型的流式输出格式为：
                     {"choices": [{"delta": {"content": "下一个字"}}]}
                     需提取 delta.content 字段。
                     注意：首个 chunk 可能 content 为空，仅表示连接建立。
                     */
                    if let choices = json["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let content = delta["content"] as? String,
                       !content.isEmpty
                    {
                        DispatchQueue.main.async { [weak self] in
                            self?.onReceive?(content) // 将增量文本传给 UI
                        }
                    }

                default:
                    print("未知 provider: \(provider)")
                }

            } else {
                print("JSON解析失败: \(trimmed)")
=======
        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines where line.starts(with: "data:") {
            let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonString == "[DONE]" {
                continue
            }

            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.onReceive?(content)
                }
            } else {
                print("⚠️ JSON解析失败: \(jsonString)")
>>>>>>> 4fa7d00ee41c189ad6e6da7dc4b0a4715a74e682
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                print("任务出错：\(error.localizedDescription)")
            }
            self?.onComplete?()
        }
    }
}
