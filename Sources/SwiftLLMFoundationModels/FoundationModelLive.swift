import Foundation
import SwiftLLM

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct FoundationModelToolConfiguration: Sendable {
  public var tools: [any Tool]

  public init(tools: [any Tool] = []) {
    self.tools = tools
  }

  public static var none: Self {
    Self()
  }

  public var isEmpty: Bool {
    tools.isEmpty
  }

  public var toolNames: [String] {
    tools.map { $0.name }
  }

  public var estimatedDefinitionTokens: Int {
    guard !tools.isEmpty else { return 0 }
    let renderedTools = tools
      .map { "\($0.name)\n\($0.description)" }
      .joined(separator: "\n\n")
    return TokenCounter.latinHeuristic.count(renderedTools)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelClient {
  public func prewarm(
    _ request: FoundationModelPrewarmRequest,
    tools: [any Tool]
  ) throws {
    try foundationModelPrewarm(
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }

  public func respond(
    to request: FoundationModelGenerationRequest,
    tools: [any Tool]
  ) async throws -> FoundationModelGenerationResponse<String> {
    try await foundationModelStringResponse(
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }

  public func respond<Content: Generable & Sendable>(
    generating type: Content.Type,
    request: FoundationModelGenerationRequest,
    tools: [any Tool] = []
  ) async throws -> FoundationModelGenerationResponse<Content> {
    try await foundationModelGeneratedResponse(
      generating: type,
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelAvailability(
  locale: Locale?,
  useCase: FoundationModelUseCase
) -> FoundationModelAvailability {
  let model = foundationModel(useCase: useCase)
  let locale = locale ?? .current
  guard model.supportsLocale(locale)
  else { return .unsupportedLocale(locale.identifier) }

  switch model.availability {
  case .available:
    return .available
  case .unavailable(.appleIntelligenceNotEnabled):
    return .appleIntelligenceNotEnabled
  case .unavailable(.deviceNotEligible):
    return .deviceNotEligible
  case .unavailable(.modelNotReady):
    return .modelNotReady
  @unknown default:
    return .unknown("The local language model is unavailable.")
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelTokenCount(
  for request: FoundationModelTokenCountRequest
) async throws -> Int {
  let model = foundationModel(useCase: request.useCase)
  guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
  else { return TokenCounter.latinHeuristic.count(request.text) }

  do {
    return try await model.tokenCount(for: Prompt(request.text))
  } catch {
    throw FoundationModelErrorNormalizer.failure(from: error)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelPrewarm(
  for request: FoundationModelPrewarmRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) throws {
  let availability = foundationModelAvailability(locale: nil, useCase: request.useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let session = LanguageModelSession(
    model: foundationModel(useCase: request.useCase),
    tools: toolConfiguration.tools,
    instructions: request.instructions
  )
  session.prewarm(promptPrefix: request.promptPrefix.map(Prompt.init))
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStringResponse(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) async throws -> FoundationModelGenerationResponse<String> {
  try await foundationModelResponse(
    for: request,
    toolConfiguration: toolConfiguration
  ) { session, options in
    let response = try await session.respond(
      to: Prompt(request.prompt.userPrompt),
      options: options
    )
    return response.content
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelGeneratedResponse<Content: Generable & Sendable>(
  generating type: Content.Type,
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) async throws -> FoundationModelGenerationResponse<Content> {
  try await foundationModelResponse(
    for: request,
    toolConfiguration: toolConfiguration
  ) { session, options in
    let response = try await session.respond(
      to: Prompt(request.prompt.userPrompt),
      generating: type,
      includeSchemaInPrompt: request.options.includeSchemaInPrompt,
      options: options
    )
    return response.content
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelResponse<Content: Sendable>(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none,
  perform: (LanguageModelSession, GenerationOptions) async throws -> Content
) async throws -> FoundationModelGenerationResponse<Content> {
  let availability = foundationModelAvailability(locale: nil, useCase: request.useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let model = foundationModel(useCase: request.useCase)
  let session = LanguageModelSession(
    model: model,
    tools: toolConfiguration.tools,
    instructions: request.prompt.systemInstructions
  )
  if let prewarmPromptPrefix = request.prewarmPromptPrefix {
    session.prewarm(promptPrefix: Prompt(prewarmPromptPrefix))
  }

  let startedAt = Date()
  let options = request.options.foundationGenerationOptions
  let estimatedInputTokens = TokenCounter.latinHeuristic.count(
    request.prompt.systemInstructions + "\n\n" + request.prompt.userPrompt
  ) + toolConfiguration.estimatedDefinitionTokens
  let measuredInputTokens = await foundationModelMeasuredTokenCount(
    request.prompt.userPrompt,
    model: model
  )

  do {
    let content = try await perform(session, options)
    let completedAt = Date()
    let renderedOutput = String(describing: content)
    let estimatedOutputTokens = request.options.maximumResponseTokens
      ?? TokenCounter.latinHeuristic.count(renderedOutput)
    let measuredOutputTokens = await foundationModelMeasuredTokenCount(
      renderedOutput,
      model: model
    )

    return FoundationModelGenerationResponse(
      content: content,
      metadata: request.prompt.metadata,
      tokenUsage: LLMTokenUsage(
        estimatedInputTokens: estimatedInputTokens,
        estimatedOutputTokens: estimatedOutputTokens,
        measuredInputTokens: measuredInputTokens,
        measuredOutputTokens: measuredOutputTokens
      ),
      startedAt: startedAt,
      completedAt: completedAt
    )
  } catch LanguageModelSession.GenerationError.refusal(let refusal, let context) {
    let explanation = try? await refusal.explanation.content
    throw FoundationModelFailure(
      reason: .refusal,
      debugDescription: explanation ?? context.debugDescription
    )
  } catch {
    throw FoundationModelErrorNormalizer.failure(from: error)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelMeasuredTokenCount(
  _ text: String,
  model: SystemLanguageModel
) async -> Int? {
  guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
  else { return nil }

  return try? await model.tokenCount(for: Prompt(text))
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModel(
  useCase: FoundationModelUseCase
) -> SystemLanguageModel {
  switch useCase {
  case .general:
    return .default
  case .contentTagging:
    return SystemLanguageModel(useCase: .contentTagging)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelFailure(
  from error: LanguageModelSession.GenerationError
) -> FoundationModelFailure {
  switch error {
  case let .assetsUnavailable(context):
    return FoundationModelFailure(reason: .assetsUnavailable, debugDescription: context.debugDescription)
  case let .concurrentRequests(context):
    return FoundationModelFailure(reason: .concurrentRequests, debugDescription: context.debugDescription)
  case let .decodingFailure(context):
    return FoundationModelFailure(reason: .decodingFailure, debugDescription: context.debugDescription)
  case let .exceededContextWindowSize(context):
    return FoundationModelFailure(reason: .contextExceeded, debugDescription: context.debugDescription)
  case let .guardrailViolation(context):
    return FoundationModelFailure(reason: .guardrailViolation, debugDescription: context.debugDescription)
  case let .rateLimited(context):
    return FoundationModelFailure(reason: .rateLimited, debugDescription: context.debugDescription)
  case let .refusal(_, context):
    return FoundationModelFailure(reason: .refusal, debugDescription: context.debugDescription)
  case let .unsupportedGuide(context):
    return FoundationModelFailure(reason: .unsupportedGuide, debugDescription: context.debugDescription)
  case let .unsupportedLanguageOrLocale(context):
    return FoundationModelFailure(
      reason: .unsupportedLanguageOrLocale,
      debugDescription: context.debugDescription
    )
  @unknown default:
    return FoundationModelFailure(
      reason: .providerError,
      debugDescription: error.localizedDescription
    )
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelGenerationOptions {
  fileprivate var foundationGenerationOptions: GenerationOptions {
    GenerationOptions(
      sampling: sampling.foundationSamplingMode,
      temperature: temperature,
      maximumResponseTokens: maximumResponseTokens
    )
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelSamplingMode {
  fileprivate var foundationSamplingMode: GenerationOptions.SamplingMode? {
    switch self {
    case .systemDefault:
      return nil
    case .greedy:
      return .greedy
    case let .randomTop(top, seed):
      return .random(top: top, seed: seed)
    case let .randomProbabilityThreshold(probabilityThreshold, seed):
      return .random(probabilityThreshold: probabilityThreshold, seed: seed)
    }
  }
}
#endif
