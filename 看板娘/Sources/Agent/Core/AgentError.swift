import Foundation

enum ModelProviderError: Error, Codable, Equatable, Sendable {
    case unavailable(String)
    case unsupportedCapability(String)
    case invalidResponse(String)
    case transport(String)
}

enum AgentError: Error, Equatable, Sendable {
    case busy
    case cancelled
    case invalidConfiguration(String)
    case maxTurnsExceeded(limit: Int)
    case modelRequestFailed(ModelProviderError)
    case modelTimedOut
    case invalidToolArguments(toolName: String, detail: String)
    case toolUnavailable(String)
    case toolTimedOut(String)
    case toolExecutionFailed(toolName: String, detail: String)
    case guardrailTriggered(GuardrailResult)
    case approvalStateInvalid
    case sessionFailure(String)
    case outputValidationFailed(String)
    case invalidJSONValue(String)
}

extension AgentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .busy: "Agent 正在处理上一项任务"
        case .cancelled: "Agent 运行已取消"
        case .invalidConfiguration(let detail): "Agent 配置无效：\(detail)"
        case .maxTurnsExceeded(let limit): "Agent 已达到最大轮次 \(limit)"
        case .modelRequestFailed(let error): "模型请求失败：\(error)"
        case .modelTimedOut: "模型请求超时"
        case .invalidToolArguments(let name, let detail): "工具 \(name) 参数无效：\(detail)"
        case .toolUnavailable(let name): "未注册的工具：\(name)"
        case .toolTimedOut(let name): "工具 \(name) 执行超时"
        case .toolExecutionFailed(let name, let detail): "工具 \(name) 执行失败：\(detail)"
        case .guardrailTriggered(let result): "安全检查已阻止运行：\(result.message)"
        case .approvalStateInvalid: "待审批的运行状态无效"
        case .sessionFailure(let detail): "Session 操作失败：\(detail)"
        case .outputValidationFailed(let detail): "输出校验失败：\(detail)"
        case .invalidJSONValue(let type): "不支持的 JSON 值类型：\(type)"
        }
    }
}
