import Foundation

public enum LLMFinishReason: String, Equatable, Sendable {
  case contentFilter
  case error
  case length
  case stop
  case toolCalls
  case unknown
}

/// A completed provider-neutral generation response.
public struct LLMResponse: Equatable, Identifiable, Sendable {
  public var finishReason: LLMFinishReason?
  public var id: String
  public var message: LLMMessage
  public var metadata: LLMProviderMetadata
  public var model: String?
  public var text: String
  public var tokenUsage: LLMTokenUsage?
  public var toolCalls: [LLMToolCall]

  public init(
    id: String = UUID().uuidString,
    text: String,
    message: LLMMessage? = nil,
    toolCalls: [LLMToolCall] = [],
    finishReason: LLMFinishReason? = nil,
    tokenUsage: LLMTokenUsage? = nil,
    model: String? = nil,
    metadata: LLMProviderMetadata
  ) {
    self.finishReason = finishReason
    self.id = id
    self.message = message ?? .assistant(text, toolCalls: toolCalls)
    self.metadata = metadata
    self.model = model
    self.text = text
    self.tokenUsage = tokenUsage
    self.toolCalls = toolCalls
  }

  public var candidate: GenerationCandidate<String> {
    GenerationCandidate(
      output: text,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

/// Streaming lifecycle events emitted by an `LLMClient`.
public enum LLMStreamEvent: Equatable, Sendable {
  case completed(LLMResponse)
  case started(LLMProviderMetadata)
  case textDelta(String)
  case toolCall(LLMToolCall)
}

public enum LLMClientErrorReason: Equatable, Sendable {
  case authentication
  case badRequest
  case cancelled
  case contextExceeded
  case decoding
  case guardrailViolation
  case network
  case provider(String)
  case rateLimited
  case unavailable
  case unsupported
}

public struct LLMClientError: LLMFallbackClassifiableError, Equatable, LocalizedError, Sendable {
  public var debugDescription: String?
  public var reason: LLMClientErrorReason
  public var statusCode: Int?

  public init(
    reason: LLMClientErrorReason,
    statusCode: Int? = nil,
    debugDescription: String? = nil
  ) {
    self.debugDescription = debugDescription
    self.reason = reason
    self.statusCode = statusCode
  }

  public var errorDescription: String? {
    switch reason {
    case .authentication:
      return "The provider rejected the configured credentials."
    case .badRequest:
      return "The provider rejected the request."
    case .cancelled:
      return "The generation request was cancelled."
    case .contextExceeded:
      return "The request exceeded the model context window."
    case .decoding:
      return "The provider response could not be decoded."
    case .guardrailViolation:
      return "The provider rejected the request or response for safety reasons."
    case .network:
      return "The provider request failed before a response was received."
    case let .provider(message):
      return message
    case .rateLimited:
      return "The provider rate-limited the request."
    case .unavailable:
      return "The provider is unavailable."
    case .unsupported:
      return "The provider does not support this request."
    }
  }

  public var fallbackReason: FallbackReason {
    switch reason {
    case .authentication, .badRequest, .provider:
      return .providerError(debugDescription ?? errorDescription ?? "Provider error.")
    case .network:
      return .unavailable
    case .cancelled:
      return .providerError("Request cancelled.")
    case .contextExceeded:
      return .contextExceeded
    case .decoding:
      return .decodingFailed
    case .guardrailViolation:
      return .guardrailViolation
    case .rateLimited:
      return .rateLimited
    case .unavailable:
      return .unavailable
    case .unsupported:
      return .unsupported
    }
  }
}
