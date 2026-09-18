import Foundation

enum AgentInstructions<Context: Sendable>: Sendable {
    case fixed(String)
    case dynamic(@Sendable (Context) async throws -> String)

    func resolve(using context: Context) async throws -> String {
        switch self {
        case .fixed(let value): value
        case .dynamic(let provider): try await provider(context)
        }
    }
}

struct AgentModelConfiguration: Codable, Equatable, Sendable {
    let providerID: String
    let modelID: String

    init(providerID: String = "default", modelID: String = "default") {
        self.providerID = providerID
        self.modelID = modelID
    }
}

struct AgentOutputDecoder<Output: Sendable>: Sendable {
    private let decodeValue: @Sendable (String) throws -> Output

    init(_ decodeValue: @escaping @Sendable (String) throws -> Output) {
        self.decodeValue = decodeValue
    }

    func decode(_ text: String) throws -> Output {
        try decodeValue(text)
    }
}

struct AgentOutputSchema: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let schema: JSONValue
    let strict: Bool

    init(
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

extension AgentOutputDecoder where Output == String {
    static var text: AgentOutputDecoder<String> { AgentOutputDecoder { $0 } }
}

extension AgentOutputDecoder where Output: Decodable {
    static var json: AgentOutputDecoder<Output> {
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

struct AgentDefinition<Context: Sendable, Output: Sendable>: Sendable {
    let id: String
    let name: String
    let instructions: AgentInstructions<Context>
    let model: AgentModelConfiguration
    let tools: [AnyAgentTool<Context>]
    let inputGuardrails: [AnyInputGuardrail<Context>]
    let outputGuardrails: [AnyOutputGuardrail<Context, Output>]
    let toolGuardrails: [AnyToolGuardrail<Context>]
    let outputSchema: AgentOutputSchema?
    let outputDecoder: AgentOutputDecoder<Output>

    init(
        id: String,
        name: String,
        instructions: AgentInstructions<Context>,
        model: AgentModelConfiguration = AgentModelConfiguration(),
        tools: [AnyAgentTool<Context>] = [],
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
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.toolGuardrails = toolGuardrails
        self.outputSchema = outputSchema
        self.outputDecoder = outputDecoder
    }
}

extension AgentDefinition where Output == String {
    init(
        id: String,
        name: String,
        instructions: AgentInstructions<Context>,
        model: AgentModelConfiguration = AgentModelConfiguration(),
        tools: [AnyAgentTool<Context>] = [],
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
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            toolGuardrails: toolGuardrails,
            outputSchema: outputSchema,
            outputDecoder: .text
        )
    }
}
