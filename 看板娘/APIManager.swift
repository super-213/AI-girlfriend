import Foundation
import SwiftUI

class APIManager: NSObject, URLSessionDataDelegate {
    @AppStorage("ai_model") private var aiModel = "glm-4v-flash"
    @AppStorage("apiKey") private var apiKey = "d9110ecebbf244aab69d3db43781f03c.W4KB9WyATuiwpYsf"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"

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

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
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
