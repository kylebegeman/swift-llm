import Foundation

public enum FallbackReason: Equatable, Sendable {
  case assetsUnavailable
  case concurrentRequest
  case decodingFailed
  case unavailable
  case unsupportedLocale
  case unsupportedGuide
  case contextExceeded
  case guardrailViolation
  case rateLimited
  case refusal
  case validationFailed
  case providerError(String)
}

public struct FallbackDecision<Output: Sendable>: Sendable {
  public var output: Output?
  public var reason: FallbackReason

  public init(output: Output?, reason: FallbackReason) {
    self.output = output
    self.reason = reason
  }
}

extension FallbackDecision: Equatable where Output: Equatable {}

public struct GenerationCandidate<Output: Sendable>: Sendable {
  public var metadata: LLMProviderMetadata
  public var output: Output
  public var tokenUsage: LLMTokenUsage?

  public init(
    output: Output,
    metadata: LLMProviderMetadata,
    tokenUsage: LLMTokenUsage? = nil
  ) {
    self.output = output
    self.metadata = metadata
    self.tokenUsage = tokenUsage
  }
}

extension GenerationCandidate: Equatable where Output: Equatable {}
