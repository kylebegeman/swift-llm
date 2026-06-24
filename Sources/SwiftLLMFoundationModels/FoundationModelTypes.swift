import Foundation
import SwiftLLM

public enum FoundationModelDefaults {
  public static let contextWindowTokens = 4_096
  public static let defaultPromptVersion = "foundation-models-v1"

  public static func metadata(
    promptVersion: String = Self.defaultPromptVersion,
    modelIdentifier: String = "SystemLanguageModel.default"
  ) -> LLMProviderMetadata {
    LLMProviderMetadata(
      modelIdentifier: modelIdentifier,
      privacyMode: .localOnly,
      promptVersion: promptVersion,
      providerDisplayName: "Apple Foundation Models",
      providerKind: .appleFoundationModels
    )
  }
}

public enum FoundationModelUseCase: String, Equatable, Sendable {
  case general
  case contentTagging
}

public enum FoundationModelAvailability: Equatable, Sendable {
  case available
  case appleIntelligenceNotEnabled
  case deviceNotEligible
  case modelNotReady
  case unsupportedLocale(String?)
  case unavailableInBuild
  case unsupportedOS
  case unknown(String)

  public var isAvailable: Bool {
    self == .available
  }

  public var fallbackReason: FallbackReason? {
    switch self {
    case .available:
      return nil
    case .unsupportedLocale:
      return .unsupportedLocale
    case .appleIntelligenceNotEnabled,
      .deviceNotEligible,
      .modelNotReady,
      .unavailableInBuild,
      .unsupportedOS,
      .unknown:
      return .unavailable
    }
  }

  public var diagnosticMessage: String {
    switch self {
    case .available:
      return "Foundation Models are available."
    case .appleIntelligenceNotEnabled:
      return "Apple Intelligence is not enabled."
    case .deviceNotEligible:
      return "This device is not eligible for Apple Intelligence."
    case .modelNotReady:
      return "The local language model is not ready."
    case let .unsupportedLocale(identifier):
      if let identifier {
        return "The local language model does not support locale \(identifier)."
      }
      return "The local language model does not support the current locale."
    case .unavailableInBuild:
      return "Foundation Models are unavailable in this build."
    case .unsupportedOS:
      return "Foundation Models require iOS 26, macOS 26, or visionOS 26."
    case let .unknown(message):
      return message
    }
  }
}

public enum FoundationModelSamplingMode: Equatable, Sendable {
  case systemDefault
  case greedy
  case randomTop(Int, seed: UInt64? = nil)
  case randomProbabilityThreshold(Double, seed: UInt64? = nil)
}

public struct FoundationModelGenerationOptions: Equatable, Sendable {
  public var includeSchemaInPrompt: Bool
  public var maximumResponseTokens: Int?
  public var sampling: FoundationModelSamplingMode
  public var temperature: Double?

  public init(
    sampling: FoundationModelSamplingMode = .greedy,
    temperature: Double? = 0.1,
    maximumResponseTokens: Int? = nil,
    includeSchemaInPrompt: Bool = true
  ) {
    self.includeSchemaInPrompt = includeSchemaInPrompt
    self.maximumResponseTokens = maximumResponseTokens
    self.sampling = sampling
    self.temperature = temperature
  }

  public static let deterministic = Self(
    sampling: .greedy,
    temperature: 0.1,
    maximumResponseTokens: nil,
    includeSchemaInPrompt: true
  )
}

public struct FoundationModelPrewarmRequest: Equatable, Sendable {
  public var instructions: String
  public var promptPrefix: String?
  public var useCase: FoundationModelUseCase

  public init(
    instructions: String,
    promptPrefix: String? = nil,
    useCase: FoundationModelUseCase = .general
  ) {
    self.instructions = instructions
    self.promptPrefix = promptPrefix
    self.useCase = useCase
  }
}

public struct FoundationModelTokenCountRequest: Equatable, Sendable {
  public var text: String
  public var useCase: FoundationModelUseCase

  public init(
    text: String,
    useCase: FoundationModelUseCase = .general
  ) {
    self.text = text
    self.useCase = useCase
  }
}

public struct FoundationModelGenerationRequest: Equatable, Sendable {
  public var options: FoundationModelGenerationOptions
  public var prompt: CompiledPrompt
  public var prewarmPromptPrefix: String?
  public var useCase: FoundationModelUseCase

  public init(
    prompt: CompiledPrompt,
    options: FoundationModelGenerationOptions = .deterministic,
    useCase: FoundationModelUseCase = .general,
    prewarmPromptPrefix: String? = nil
  ) {
    self.options = options
    self.prompt = prompt
    self.prewarmPromptPrefix = prewarmPromptPrefix ?? prompt.contextPlan?.prewarmPromptPrefix
    self.useCase = useCase
  }
}

public struct FoundationModelGenerationResponse<Content: Sendable>: Sendable {
  public var completedAt: Date
  public var content: Content
  public var metadata: LLMProviderMetadata
  public var startedAt: Date
  public var tokenUsage: LLMTokenUsage

  public init(
    content: Content,
    metadata: LLMProviderMetadata,
    tokenUsage: LLMTokenUsage,
    startedAt: Date,
    completedAt: Date
  ) {
    self.completedAt = completedAt
    self.content = content
    self.metadata = metadata
    self.startedAt = startedAt
    self.tokenUsage = tokenUsage
  }

  public var candidate: GenerationCandidate<Content> {
    GenerationCandidate(
      output: content,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

extension FoundationModelGenerationResponse: Equatable where Content: Equatable {}
