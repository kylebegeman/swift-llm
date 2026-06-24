import Foundation
import SwiftLLM

public enum FoundationModelFailureReason: Equatable, Sendable {
  case assetsUnavailable
  case concurrentRequests
  case contextExceeded
  case decodingFailure
  case guardrailViolation
  case rateLimited
  case refusal
  case toolCallFailed
  case unavailable(FoundationModelAvailability)
  case unsupportedGuide
  case unsupportedLanguageOrLocale
  case providerError
}

public struct FoundationModelFailure: LLMFallbackClassifiableError, Equatable, LocalizedError, Sendable {
  public var debugDescription: String?
  public var reason: FoundationModelFailureReason

  public init(
    reason: FoundationModelFailureReason,
    debugDescription: String? = nil
  ) {
    self.debugDescription = debugDescription
    self.reason = reason
  }

  public var errorDescription: String? {
    switch reason {
    case .assetsUnavailable:
      return "Foundation Models assets are unavailable."
    case .concurrentRequests:
      return "The Foundation Models session is already responding."
    case .contextExceeded:
      return "The request exceeded the Foundation Models context window."
    case .decodingFailure:
      return "Foundation Models could not decode the generated structured response."
    case .guardrailViolation:
      return "Foundation Models guardrails rejected the request or response."
    case .rateLimited:
      return "Foundation Models rate-limited the request."
    case .refusal:
      return "Foundation Models refused the request."
    case .toolCallFailed:
      return "A Foundation Models tool call failed."
    case let .unavailable(availability):
      return availability.diagnosticMessage
    case .unsupportedGuide:
      return "The request used a generation guide Foundation Models does not support."
    case .unsupportedLanguageOrLocale:
      return "Foundation Models does not support the requested language or locale."
    case .providerError:
      return "Foundation Models failed to generate a response."
    }
  }

  public var fallbackReason: FallbackReason {
    switch reason {
    case .assetsUnavailable:
      return .assetsUnavailable
    case .concurrentRequests:
      return .concurrentRequest
    case .contextExceeded:
      return .contextExceeded
    case .decodingFailure:
      return .decodingFailed
    case .guardrailViolation:
      return .guardrailViolation
    case .rateLimited:
      return .rateLimited
    case .refusal:
      return .refusal
    case .toolCallFailed:
      return .providerError(debugDescription ?? "Tool call failed.")
    case let .unavailable(availability):
      return availability.fallbackReason ?? .unavailable
    case .unsupportedGuide:
      return .unsupportedGuide
    case .unsupportedLanguageOrLocale:
      return .unsupportedLocale
    case .providerError:
      return .providerError(debugDescription ?? "Foundation Models failed.")
    }
  }
}
