import Foundation
import SwiftUI

class APIManager: NSObject, URLSessionDataDelegate {
    @AppStorage("ai_model") private var aiModel = "glm-4v-flash"
    @AppStorage("apiKey") private var apiKey = "d9110ecebbf244aab69d3db43781f03c.W4KB9WyATuiwpYsf"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var receivedData = Data()

    func sendStreamRequest(userInput: String, onReceive: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        let apiUrl = apiUrl

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
                        "enable": true,
                        "search_engine":"search_std"
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

        // 初始化 URLSession
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: request)
        task?.resume()

        // 存储回调函数
        self.onReceive = onReceive
        self.onComplete = onComplete
    }

    // MARK: - URLSessionDataDelegate Methods

    private var onReceive: ((String) -> Void)?
    private var onComplete: (() -> Void)?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        parsePartialStreamData(onReceive: onReceive)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("任务完成时发生错误：\(error.localizedDescription)")
        } else {
            DispatchQueue.main.async {
                self.onComplete?() // 流结束
            }
        }

        // 清理资源
        self.receivedData.removeAll()
        self.task = nil
        self.session.finishTasksAndInvalidate()
    }

    // MARK: - Partial Stream Parsing

    private func parsePartialStreamData(onReceive: ((String) -> Void)?) {
        let fullString = String(data: receivedData, encoding: .utf8) ?? ""
        let lines = fullString.components(separatedBy: "\n").filter { !$0.isEmpty }

        var newData = Data()
        for line in lines {
            if line.starts(with: "data:") {
                let jsonDataString = String(line.dropFirst(5)) // 去掉 "data:" 前缀
                if jsonDataString == "[DONE]" {
                    continue // 忽略 [DONE] 行
                }

                if let jsonData = jsonDataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    DispatchQueue.main.async {
                        onReceive?(content) // 实时更新内容
                    }
                } else {
                    print("Failed to parse JSON: \(jsonDataString)") // 打印解析失败的日志
                }
            }
        }

        // 更新剩余未解析的数据
        if let lastLine = lines.last, !lastLine.hasPrefix("data:") {
            if let range = fullString.range(of: lastLine) {
                let startIndex = fullString.distance(from: fullString.startIndex, to: range.lowerBound)
                newData = receivedData.subdata(in: startIndex..<receivedData.count)
            }
        }
        receivedData = newData
    }
}
