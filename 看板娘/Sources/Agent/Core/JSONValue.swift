import Foundation

/// A Sendable, Codable representation of arbitrary JSON used at Core boundaries.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(any value: Any) throws {
        switch value {
        case let value as [String: Any]:
            self = .object(try value.mapValues(JSONValue.init(any:)))
        case let value as [Any]:
            self = .array(try value.map(JSONValue.init(any:)))
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self = CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue)
                : .number(value.doubleValue)
        case _ as NSNull:
            self = .null
        default:
            throw AgentError.invalidJSONValue(String(describing: type(of: value)))
        }
    }

    var foundationValue: Any {
        switch self {
        case .object(let value): value.mapValues(\.foundationValue)
        case .array(let value): value.map(\.foundationValue)
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        }
    }
}
