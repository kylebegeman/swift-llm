import Foundation

public enum LLMPrivacyMode: String, Equatable, Sendable {
  case localOnly
  case localWithUserSelectedContext
  case externalOptIn
}

public enum LLMProviderKind: String, Equatable, Sendable {
  case appleFoundationModels
  case deterministicLocal
  case external
  case testDouble
}

public struct LLMProviderMetadata: Equatable, Sendable {
  public var modelIdentifier: String?
  public var privacyMode: LLMPrivacyMode
  public var promptVersion: String
  public var providerConfigurationID: String?
  public var providerDisplayName: String
  public var providerKind: LLMProviderKind

  public init(
    modelIdentifier: String? = nil,
    privacyMode: LLMPrivacyMode,
    promptVersion: String,
    providerConfigurationID: String? = nil,
    providerDisplayName: String,
    providerKind: LLMProviderKind
  ) {
    self.modelIdentifier = modelIdentifier
    self.privacyMode = privacyMode
    self.promptVersion = promptVersion
    self.providerConfigurationID = providerConfigurationID
    self.providerDisplayName = providerDisplayName
    self.providerKind = providerKind
  }
}

public struct LLMGenerationRun: Equatable, Identifiable, Sendable {
  public var completedAt: Date?
  public var id: UUID
  public var metadata: LLMProviderMetadata
  public var startedAt: Date
  public var status: LLMRunStatus
  public var tokenUsage: LLMTokenUsage?

  public init(
    completedAt: Date? = nil,
    id: UUID,
    metadata: LLMProviderMetadata,
    startedAt: Date,
    status: LLMRunStatus,
    tokenUsage: LLMTokenUsage? = nil
  ) {
    self.completedAt = completedAt
    self.id = id
    self.metadata = metadata
    self.startedAt = startedAt
    self.status = status
    self.tokenUsage = tokenUsage
  }
}

public enum LLMRunStatus: String, Equatable, Sendable {
  case pending
  case running
  case succeeded
  case failed
  case fellBack
}

public struct LLMTokenUsage: Equatable, Sendable {
  public var estimatedInputTokens: Int
  public var estimatedOutputTokens: Int
  public var measuredInputTokens: Int?
  public var measuredOutputTokens: Int?

  public init(
    estimatedInputTokens: Int,
    estimatedOutputTokens: Int,
    measuredInputTokens: Int? = nil,
    measuredOutputTokens: Int? = nil
  ) {
    self.estimatedInputTokens = estimatedInputTokens
    self.estimatedOutputTokens = estimatedOutputTokens
    self.measuredInputTokens = measuredInputTokens
    self.measuredOutputTokens = measuredOutputTokens
  }
}

public struct LLMError: Error, Equatable, LocalizedError, Sendable {
  public var message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? {
    message
  }
}
