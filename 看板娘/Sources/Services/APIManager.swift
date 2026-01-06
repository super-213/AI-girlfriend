import Foundation
import SwiftUI

final class APIManager: NSObject, URLSessionDataDelegate {
    
    // MARK: - 配置存储
    
    @AppStorage("ai_model") private var aiModel = "glm-4v-flash"
    @AppStorage("apiKey") private var apiKey = "<默认API Key>"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
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

    // MARK: - URL 会话数据委托

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
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
                    print("未知 provider: \(provider)")
                }

            } else {
                print("JSON解析失败: \(trimmed)")
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
