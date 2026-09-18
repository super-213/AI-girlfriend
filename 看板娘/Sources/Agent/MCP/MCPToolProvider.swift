import Foundation

struct MCPToolProvider<Context: Sendable>: Sendable {
    let server: MCPServerConfiguration
    let client: any MCPToolClient
    let approvalPolicy: MCPApprovalPolicy
    let filter: MCPToolFilter

    init(
        server: MCPServerConfiguration,
        client: any MCPToolClient,
        approvalPolicy: MCPApprovalPolicy = .mutations,
        filter: MCPToolFilter = MCPToolFilter()
    ) {
        self.server = server
        self.client = client
        self.approvalPolicy = approvalPolicy
        self.filter = filter
    }

    func tools() async throws -> [AnyAgentTool<Context>] {
        try server.validate()
        return try await client.listTools(server: server)
            .filter(filter.allows)
            .map(makeTool)
    }

    private func makeTool(_ descriptor: MCPToolDescriptor) -> AnyAgentTool<Context> {
        let modelName = "mcp_\(normalize(server.id))_\(normalize(descriptor.name))"
        let requiresApproval = approvalPolicy.requiresApproval(tool: descriptor)
        let behavior = ToolBehavior(
            isReadOnly: descriptor.isReadOnly,
            isIdempotent: descriptor.isIdempotent,
            hasExternalSideEffects: descriptor.hasExternalSideEffects,
            requiresApproval: requiresApproval,
            allowsParallelExecution: descriptor.isReadOnly
                && descriptor.isIdempotent
                && !descriptor.hasExternalSideEffects,
            defaultTimeout: nil,
            allowsAutomaticRetry: descriptor.isReadOnly && descriptor.isIdempotent,
            riskLevel: requiresApproval ? .high : .low
        )
        return AnyAgentTool(
            definition: ToolDefinition(
                name: modelName,
                description: "[MCP \(server.label)] \(descriptor.description)",
                parameters: descriptor.inputSchema
            ),
            behavior: behavior,
            approvalSummary: { _ in
                "允许 MCP Server \(server.label) 执行 \(descriptor.name)"
            },
            invoke: { _, rawArguments in
                guard let data = rawArguments.data(using: .utf8) else {
                    throw AgentError.invalidToolArguments(
                        toolName: modelName,
                        detail: "MCP 参数不是有效 JSON"
                    )
                }
                let object: Any
                do {
                    object = try JSONSerialization.jsonObject(
                        with: data,
                        options: [.fragmentsAllowed]
                    )
                } catch {
                    throw AgentError.invalidToolArguments(
                        toolName: modelName,
                        detail: "MCP 参数不是有效 JSON"
                    )
                }
                let arguments = try JSONValue(any: object)
                let result = try await client.callTool(
                    server: server,
                    name: descriptor.name,
                    arguments: arguments
                )
                if result.isError {
                    throw AgentError.toolExecutionFailed(
                        toolName: modelName,
                        detail: TraceRedactor.summary(result.content)
                    )
                }
                return ToolInvocationOutput(
                    content: result.content,
                    imagePaths: result.imagePaths
                )
            }
        )
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
        }.joined()
    }
}
