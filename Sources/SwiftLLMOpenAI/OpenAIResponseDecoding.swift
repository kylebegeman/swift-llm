import Foundation
import SwiftLLM

extension OpenAIClient {
  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    let httpRequest = try responsesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    do {
      return try JSONDecoder.provider.decode(OpenAIResponsePayload.self, from: httpResponse.body)
        .llmResponse(metadata: metadata(for: request))
    } catch let error as LLMClientError {
      throw error
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "OpenAI response decoding failed: \(error.localizedDescription)"
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

  static func validate(_ response: OpenAIHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      let providerMessage = (try? JSONDecoder.provider.decode(OpenAIErrorPayload.self, from: response.body))
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
      return .provider(providerMessage ?? "OpenAI request failed with HTTP \(statusCode).")
    }
  }
}

// MARK: - Response Decoding

struct OpenAIResponsePayload: Decodable {
  var error: OpenAIProviderError?
  var finishReason: String?
  var id: String?
  var model: String?
  var output: [OpenAIOutputItem]?
  var outputText: String?
  var status: String?
  var usage: OpenAIUsage?

  enum CodingKeys: String, CodingKey {
    case error
    case finishReason = "finish_reason"
    case id
    case model
    case output
    case outputText = "output_text"
    case status
    case usage
  }

  func llmResponse(metadata: LLMProviderMetadata) throws -> LLMResponse {
    if status == "failed" {
      let message = error?.message ?? "OpenAI response failed."
      throw LLMClientError(
        reason: .provider(message),
        debugDescription: message
      )
    }

    let toolCalls = output?.compactMap(\.toolCall) ?? []
    let text = outputText ?? output?.flatMap(\.textParts).joined(separator: "\n") ?? ""
    return LLMResponse(
      id: id ?? UUID().uuidString,
      text: text,
      toolCalls: toolCalls,
      finishReason: mappedFinishReason,
      tokenUsage: usage?.tokenUsage,
      model: model ?? metadata.modelIdentifier,
      metadata: metadata
    )
  }

  private var mappedFinishReason: LLMFinishReason? {
    switch finishReason ?? status {
    case "completed":
      return .stop
    case "incomplete", "length":
      return .length
    case "content_filter":
      return .contentFilter
    case "tool_calls":
      return .toolCalls
    case nil:
      return nil
    default:
      return .unknown
    }
  }
}

struct OpenAIOutputItem: Decodable {
  var arguments: String?
  var callID: String?
  var content: [OpenAIOutputContent]?
  var id: String?
  var name: String?
  var type: String?

  enum CodingKeys: String, CodingKey {
    case arguments
    case callID = "call_id"
    case content
    case id
    case name
    case type
  }

  var textParts: [String] {
    content?.compactMap(\.text) ?? []
  }

  var toolCall: LLMToolCall? {
    guard type == "function_call",
          let name,
          let arguments
    else { return nil }
    return LLMToolCall(
      id: callID ?? id ?? UUID().uuidString,
      name: name,
      argumentsJSON: arguments
    )
  }
}

struct OpenAIOutputContent: Decodable {
  var text: String?
  var type: String?
}

struct OpenAIUsage: Decodable {
  var inputTokens: Int?
  var inputTokensDetails: OpenAIInputTokensDetails?
  var outputTokens: Int?
  var outputTokensDetails: OpenAIOutputTokensDetails?

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case inputTokensDetails = "input_tokens_details"
    case outputTokens = "output_tokens"
    case outputTokensDetails = "output_tokens_details"
  }

  var tokenUsage: LLMTokenUsage {
    LLMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens,
      cachedInputTokens: inputTokensDetails?.cachedTokens,
      reasoningTokens: outputTokensDetails?.reasoningTokens
    )
  }
}

struct OpenAIInputTokensDetails: Decodable {
  var cachedTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
  }
}

struct OpenAIOutputTokensDetails: Decodable {
  var reasoningTokens: Int?

  enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }
}

struct OpenAIStreamEvent: Decodable {
  var delta: String?
  var error: OpenAIProviderError?
  var item: OpenAIOutputItem?
  var response: OpenAIResponsePayload?
  var type: String?
}

struct OpenAIErrorPayload: Decodable {
  var error: OpenAIProviderError
}

struct OpenAIProviderError: Decodable {
  var message: String?
}
