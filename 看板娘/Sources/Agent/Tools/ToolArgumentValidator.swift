import CoreFoundation
import Foundation

enum ToolArgumentValidator {
    static func validate(_ rawArguments: String, definition: ToolDefinition) throws {
        guard let data = rawArguments.data(using: .utf8) else {
            throw AgentError.invalidToolArguments(
                toolName: definition.name,
                detail: "参数不是 UTF-8 文本"
            )
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AgentError.invalidToolArguments(
                toolName: definition.name,
                detail: "JSON 解析失败：\(error.localizedDescription)"
            )
        }
        do {
            try validate(value, schema: definition.parameters, path: "$")
        } catch let error as ValidationError {
            throw AgentError.invalidToolArguments(toolName: definition.name, detail: error.message)
        }
    }

    private struct ValidationError: Error {
        let message: String
    }

    private static func validate(_ value: Any, schema: JSONValue, path: String) throws {
        guard case .object(let object) = schema else { return }

        if case .array(let variants)? = object["anyOf"] {
            if variants.contains(where: { variant in
                (try? validate(value, schema: variant, path: path)) != nil
            }) == false {
                throw ValidationError(message: "\(path) 不匹配 anyOf 中的任一 Schema")
            }
        }

        if case .string(let type)? = object["type"] {
            guard matches(value, type: type) else {
                throw ValidationError(message: "\(path) 应为 \(type)")
            }
        }

        guard let dictionary = value as? [String: Any] else { return }
        if case .array(let required)? = object["required"] {
            for keyValue in required {
                guard case .string(let key) = keyValue else { continue }
                guard dictionary[key] != nil else {
                    throw ValidationError(message: "\(path) 缺少必填字段 \(key)")
                }
            }
        }

        let properties: [String: JSONValue]
        if case .object(let value)? = object["properties"] { properties = value }
        else { properties = [:] }
        if object["additionalProperties"] == .bool(false) {
            let extras = Set(dictionary.keys).subtracting(properties.keys)
            if let extra = extras.sorted().first {
                throw ValidationError(message: "\(path) 包含未声明字段 \(extra)")
            }
        }
        for (key, childSchema) in properties {
            guard let child = dictionary[key] else { continue }
            try validate(child, schema: childSchema, path: "\(path).\(key)")
        }
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean":
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        case "integer":
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return number.doubleValue.rounded() == number.doubleValue
        case "number":
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) != CFBooleanGetTypeID() && number.doubleValue.isFinite
        case "null": return value is NSNull
        default: return true
        }
    }
}
