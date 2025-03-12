import Foundation
import SwiftUI

class APIManager {
    @AppStorage("ai_model") private var aiModel = "glm-4v-flash"
    @AppStorage("apiKey") private var apiKey = "请删除并替换自己的API key"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"

    func sendStreamRequest(userInput: String, onReceive: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        let apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        
        // 创建请求内容
        let requestBody: [String: Any] = [
            "model": aiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userInput]
            ],
            "top_p": 0.7,
            "temperature": 0.9,
            "stream": true, // 流式输出
            "tools":[
                [
                    "type":"web_search",
                    "web_search": [
                        "enable": true
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

        // 创建数据任务
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("网络错误：\(error.localizedDescription)")
                    onComplete()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("无效的 HTTP 响应")
                    onComplete()
                    return
                }

                if httpResponse.statusCode != 200 {
                    print("HTTP 错误：\(httpResponse.statusCode)")
                    onComplete()
                    return
                }

                guard let data = data else {
                    print("未收到数据")
                    onComplete()
                    return
                }

                // 解析流式数据
                self.parseStreamData(data: data, onReceive: onReceive, onComplete: onComplete)
            }
        }

        task.resume()
    }
    
    private func parseStreamData(data: Data, onReceive: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        let fullString = String(data: data, encoding: .utf8) ?? ""
        let lines = fullString.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            if line.starts(with: "data:") {
                let jsonDataString = String(line.dropFirst(5)) // 去掉 "data:" 前缀
                if jsonDataString == "[DONE]" {
                    onComplete() // 流结束
                    return
                }

                if let jsonData = jsonDataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    onReceive(content) // 逐步接收文本
                }
            }
        }
    }
}
