import Foundation
import SwiftLLM

extension AnthropicClient {
  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    let httpRequest = try messagesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    do {
      return try JSONDecoder.provider.decode(AnthropicMessageResponse.self, from: httpResponse.body)
        .llmResponse(metadata: metadata(for: request))
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "Anthropic response decoding failed: \(error.localizedDescription)"
      )
    }
  }

  func metadata(for request: LLMRequest) -> LLMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  static func validate(_ response: AnthropicHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      let providerMessage = (try? JSONDecoder.provider.decode(AnthropicErrorPayload.self, from: response.body))
        .flatMap(\.error.message)
      throw LLMClientError(
        reason: errorReason(forStatusCode: response.statusCode, providerMessage: providerMessage),
        statusCode: response.statusCode,
        debugDescription: providerMessage
      )
    }
  }

  static func errorReason(
    forStatusCode statusCode: Int,
    providerMessage: String?
  ) -> LLMClientErrorReason {
    switch statusCode {
    case 400:
      if providerMessage?.localizedCaseInsensitiveContains("context") == true {
        return .contextExceeded
      }
      return .badRequest
    case 401, 403:
      return .authentication
    case 408, 499:
      return .cancelled
    case 429:
      return .rateLimited
    case 500...599:
      return .unavailable
    default:
      return .provider(providerMessage ?? "Anthropic request failed with HTTP \(statusCode).")
    }
  }
}

// MARK: - Response Decoding

struct AnthropicMessageResponse: Decodable {
  var content: [AnthropicContentBlock]
  var id: String
  var model: String?
  var stopReason: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case content
    case id
    case model
    case stopReason = "stop_reason"
    case usage
  }

  func llmResponse(metadata: LLMProviderMetadata) -> LLMResponse {
    let text = content.compactMap(\.text).joined(separator: "\n")
    return LLMResponse(
      id: id,
      text: text,
      toolCalls: content.compactMap(\.toolCall),
      finishReason: mappedFinishReason,
      tokenUsage: usage?.tokenUsage,
      model: model ?? metadata.modelIdentifier,
      metadata: metadata
    )
  }

  private var mappedFinishReason: LLMFinishReason? {
    stopReason?.anthropicFinishReason
  }
}

struct AnthropicContentBlock: Decodable {
  var id: String?
  var input: JSONValue?
  var name: String?
  var text: String?
  var type: String

  var toolCall: LLMToolCall? {
    guard type == "tool_use",
          let id,
          let name
    else { return nil }
    let argumentsData = (try? JSONEncoder.provider.encode(input ?? .object([:]))) ?? Data("{}".utf8)
    return LLMToolCall(
      id: id,
      name: name,
      argumentsJSON: String(decoding: argumentsData, as: UTF8.self)
    )
  }
}

struct AnthropicUsage: Decodable {
  var cacheCreationInputTokens: Int?
  var cacheReadInputTokens: Int?
  var inputTokens: Int?
  var outputTokens: Int?
  var outputTokensDetails: AnthropicOutputTokensDetails?

  enum CodingKeys: String, CodingKey {
    case cacheCreationInputTokens = "cache_creation_input_tokens"
    case cacheReadInputTokens = "cache_read_input_tokens"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case outputTokensDetails = "output_tokens_details"
  }

  var tokenUsage: LLMTokenUsage {
    LLMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens,
      cachedInputTokens: cacheReadInputTokens,
      reasoningTokens: outputTokensDetails?.thinkingTokens
    )
  }
}

struct AnthropicOutputTokensDetails: Decodable {
  var thinkingTokens: Int?

  enum CodingKeys: String, CodingKey {
    case thinkingTokens = "thinking_tokens"
  }
}

struct AnthropicStreamEvent: Decodable {
  var contentBlock: AnthropicContentBlock?
  var delta: AnthropicStreamDelta?
  var error: AnthropicProviderError?
  var index: Int?
  var message: AnthropicStreamMessage?
  var type: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case contentBlock = "content_block"
    case delta
    case error
    case index
    case message
    case type
    case usage
  }
}

struct AnthropicStreamDelta: Decodable {
  var partialJSON: String?
  var stopReason: String?
  var text: String?
  var type: String?

  enum CodingKeys: String, CodingKey {
    case partialJSON = "partial_json"
    case stopReason = "stop_reason"
    case text
    case type
  }
}

struct AnthropicStreamMessage: Decodable {
  var usage: AnthropicUsage?
}

struct AnthropicErrorPayload: Decodable {
  var error: AnthropicProviderError
}

struct AnthropicProviderError: Decodable {
  var message: String?
}
