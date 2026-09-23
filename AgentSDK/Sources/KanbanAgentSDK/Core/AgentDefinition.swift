import Foundation

public enum AgentInstructions<Context: Sendable>: Sendable {
    case fixed(String)
    case dynamic(@Sendable (Context) async throws -> String)

    public func resolve(using context: Context) async throws -> String {
        switch self {
        case .fixed(let value): value
        case .dynamic(let provider): try await provider(context)
        }
    }
}

public struct AgentModelConfiguration: Codable, Equatable, Sendable {
    public let providerID: String
    public let modelID: String

    public init(providerID: String = "default", modelID: String = "default") {
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct AgentOutputDecoder<Output: Sendable>: Sendable {
    private let decodeValue: @Sendable (String) throws -> Output

    public init(_ decodeValue: @escaping @Sendable (String) throws -> Output) {
        self.decodeValue = decodeValue
    }

    public func decode(_ text: String) throws -> Output {
        try decodeValue(text)
    }
}

public struct AgentOutputSchema: Codable, Equatable, Sendable {
    public let name: String
    public let description: String?
    public let schema: JSONValue
    public let strict: Bool

    public init(
        name: String,
        description: String? = nil,
        schema: JSONValue,
        strict: Bool = true
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.strict = strict
    }
}

public extension AgentOutputDecoder where Output == String {
    static var text: AgentOutputDecoder<String> { AgentOutputDecoder { $0 } }
}

extension AgentOutputDecoder where Output: Decodable {
    public static var json: AgentOutputDecoder<Output> {
        AgentOutputDecoder { text in
            guard let data = text.data(using: .utf8) else {
                throw AgentError.outputValidationFailed("输出不是 UTF-8 文本")
            }
            do {
                return try JSONDecoder().decode(Output.self, from: data)
            } catch {
                throw AgentError.outputValidationFailed(error.localizedDescription)
            }
        }
    }
}

public struct AgentDefinition<Context: Sendable, Output: Sendable>: Sendable {
    public let id: String
    public let name: String
    public let instructions: AgentInstructions<Context>
    public let model: AgentModelConfiguration
    public let tools: [AnyAgentTool<Context>]
    public let handoffs: [AgentHandoff<Context, Output>]
    public let inputGuardrails: [AnyInputGuardrail<Context>]
    public let outputGuardrails: [AnyOutputGuardrail<Context, Output>]
    public let toolGuardrails: [AnyToolGuardrail<Context>]
    public let outputSchema: AgentOutputSchema?
    public let outputDecoder: AgentOutputDecoder<Output>

    public init(
        id: String,
        name: String,
        instructions: AgentInstructions<Context>,
        model: AgentModelConfiguration = AgentModelConfiguration(),
        tools: [AnyAgentTool<Context>] = [],
        handoffs: [AgentHandoff<Context, Output>] = [],
        inputGuardrails: [AnyInputGuardrail<Context>] = [],
        outputGuardrails: [AnyOutputGuardrail<Context, Output>] = [],
        toolGuardrails: [AnyToolGuardrail<Context>] = [],
        outputSchema: AgentOutputSchema? = nil,
        outputDecoder: AgentOutputDecoder<Output>
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.model = model
        self.tools = tools
        self.handoffs = handoffs
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.toolGuardrails = toolGuardrails
        self.outputSchema = outputSchema
        self.outputDecoder = outputDecoder
    }
}

public extension AgentDefinition where Output == String {
    init(
        id: String,
        name: String,
        instructions: AgentInstructions<Context>,
        model: AgentModelConfiguration = AgentModelConfiguration(),
        tools: [AnyAgentTool<Context>] = [],
        handoffs: [AgentHandoff<Context, String>] = [],
        inputGuardrails: [AnyInputGuardrail<Context>] = [],
        outputGuardrails: [AnyOutputGuardrail<Context, String>] = [],
        toolGuardrails: [AnyToolGuardrail<Context>] = [],
        outputSchema: AgentOutputSchema? = nil
    ) {
        self.init(
            id: id,
            name: name,
            instructions: instructions,
            model: model,
            tools: tools,
            handoffs: handoffs,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            toolGuardrails: toolGuardrails,
            outputSchema: outputSchema,
            outputDecoder: .text
        )
    }
}
