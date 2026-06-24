import Foundation
import SwiftLLM

extension FoundationModelClient: LLMClient {
  public var capabilities: LLMClientCapabilities {
    var capabilities = LLMClientCapabilities.foundationModelsProviderNeutral
    capabilities.contextWindowTokens = FoundationModelDefaults.contextWindowTokens
    return capabilities
  }

  public var metadata: LLMProviderMetadata {
    FoundationModelDefaults.metadata()
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    try Self.validateSupportedFeatures(for: request)

    let responseMetadata = metadata(for: request)
    let prompt = CompiledPrompt(
      contract: PromptContract(
        id: request.metadata["promptID"] ?? "llm-request",
        version: responseMetadata.promptVersion,
        instructions: Self.instructions(for: request),
        responseSchemaDescription: request.responseFormat.foundationPromptDescription ?? ""
      ),
      contextPlan: request.contextPlan,
      metadata: responseMetadata,
      userPrompt: request.messages.foundationUserPrompt
    )
    let response = try await respond(
      FoundationModelGenerationRequest(
        prompt: prompt,
        options: FoundationModelGenerationOptions(
          sampling: request.parameters.temperature == 0 ? .greedy : .systemDefault,
          temperature: request.parameters.temperature,
          maximumResponseTokens: request.parameters.maxOutputTokens,
          includeSchemaInPrompt: true
        )
      )
    )

    return LLMResponse(
      text: response.content,
      finishReason: .stop,
      tokenUsage: response.tokenUsage,
      model: response.metadata.modelIdentifier,
      metadata: response.metadata
    )
  }

  private func metadata(for request: LLMRequest) -> LLMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  private static func validateSupportedFeatures(for request: LLMRequest) throws {
    if !request.tools.isEmpty ||
      request.toolChoice?.requiresToolSupport == true ||
      request.messages.contains(where: { $0.role == .tool || !$0.toolCalls.isEmpty })
    {
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LLMClient adapter describes tool-call context, but native FoundationModels tool execution still requires typed Tool wrappers."
      )
    }

    if request.parameters.topP != nil {
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LLMClient adapter does not support top-p sampling."
      )
    }

    if !request.parameters.stopSequences.isEmpty {
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LLMClient adapter does not support stop sequences."
      )
    }
  }

  private static func instructions(for request: LLMRequest) -> String {
    let roleInstructions = request.messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    return [request.instructions, roleInstructions, request.responseFormat.foundationPromptDescription]
      .compactMap { text in
        guard let text, !text.isEmpty else { return nil }
        return text
      }
      .joined(separator: "\n\n")
  }
}

private extension Array where Element == LLMMessage {
  var foundationUserPrompt: String {
    filter { $0.role != .system && $0.role != .developer }
      .map { message in
        switch message.role {
        case .assistant:
          return "Assistant:\n\(message.content)"
        case .tool:
          return "Tool result\(message.toolCallID.map { " \($0)" } ?? ""):\n\(message.content)"
        case .user:
          return message.content
        case .developer, .system:
          return message.content
        }
      }
      .joined(separator: "\n\n")
  }
}

private extension LLMResponseFormat {
  var foundationPromptDescription: String? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return "Return only valid JSON."
    case let .jsonSchema(schema):
      let encodedSchema = (try? JSONEncoder.foundationPromptEncoder.encode(schema.schema))
        .map { String(decoding: $0, as: UTF8.self) }
        ?? "{}"
      return """
      Return only valid JSON matching this schema.
      Schema name: \(schema.name)
      \(schema.description.map { "Description: \($0)\n" } ?? "")Schema:
      \(encodedSchema)
      """
    }
  }
}

private extension JSONEncoder {
  static var foundationPromptEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
