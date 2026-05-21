import Foundation
import SwiftLLM

#if canImport(FoundationModels)
import FoundationModels
#endif

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
    self.prewarmPromptPrefix = prewarmPromptPrefix
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

public struct FoundationModelClient: Sendable {
  public var checkAvailability: @Sendable (Locale?, FoundationModelUseCase) -> FoundationModelAvailability
  public var countTokens: @Sendable (FoundationModelTokenCountRequest) async throws -> Int
  public var prewarm: @Sendable (FoundationModelPrewarmRequest) async throws -> Void
  public var respond: @Sendable (FoundationModelGenerationRequest) async throws
    -> FoundationModelGenerationResponse<String>

  public init(
    checkAvailability: @escaping @Sendable (
      Locale?,
      FoundationModelUseCase
    ) -> FoundationModelAvailability,
    countTokens: @escaping @Sendable (FoundationModelTokenCountRequest) async throws -> Int,
    prewarm: @escaping @Sendable (FoundationModelPrewarmRequest) async throws -> Void,
    respond: @escaping @Sendable (FoundationModelGenerationRequest) async throws
      -> FoundationModelGenerationResponse<String>
  ) {
    self.checkAvailability = checkAvailability
    self.countTokens = countTokens
    self.prewarm = prewarm
    self.respond = respond
  }

  public func availability(
    locale: Locale? = nil,
    useCase: FoundationModelUseCase = .general
  ) -> FoundationModelAvailability {
    checkAvailability(locale, useCase)
  }

  public func tokenCounter(
    useCase: FoundationModelUseCase = .general
  ) -> TokenCounter {
    TokenCounter { text in
      // TokenCounter is synchronous. Use the live async `countTokens` API when exact
      // Foundation Models accounting is required.
      TokenCounter.latinHeuristic.count(text)
    }
  }

  public static let unavailable = Self(
    checkAvailability: { _, _ in .unavailableInBuild },
    countTokens: { request in
      TokenCounter.latinHeuristic.count(request.text)
    },
    prewarm: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    },
    respond: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    }
  )

  public static let live: Self = {
    #if canImport(FoundationModels)
    Self(
      checkAvailability: { locale, useCase in
        foundationModelAvailability(locale: locale, useCase: useCase)
      },
      countTokens: { request in
        try await foundationModelTokenCount(for: request)
      },
      prewarm: { request in
        try foundationModelPrewarm(for: request)
      },
      respond: { request in
        try await foundationModelStringResponse(for: request)
      }
    )
    #else
    Self.unavailable
    #endif
  }()
}

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
        debugDescription: "FoundationModelClient's provider-neutral LLMClient adapter does not support tool calling yet."
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

public enum FoundationModelErrorNormalizer {
  public static func failure(from error: any Error) -> FoundationModelFailure {
    if let failure = error as? FoundationModelFailure {
      return failure
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
      if let generationError = error as? LanguageModelSession.GenerationError {
        return foundationModelFailure(from: generationError)
      }
      if let toolError = error as? LanguageModelSession.ToolCallError {
        return FoundationModelFailure(
          reason: .toolCallFailed,
          debugDescription: toolError.errorDescription ?? String(describing: toolError.underlyingError)
        )
      }
    }
    #endif

    return FoundationModelFailure(
      reason: .providerError,
      debugDescription: error.localizedDescription
    )
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

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelClient {
  public func respond<Content: Generable & Sendable>(
    generating type: Content.Type,
    request: FoundationModelGenerationRequest
  ) async throws -> FoundationModelGenerationResponse<Content> {
    try await foundationModelGeneratedResponse(generating: type, for: request)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelAvailability(
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
private func foundationModelTokenCount(
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
private func foundationModelPrewarm(
  for request: FoundationModelPrewarmRequest
) throws {
  let availability = foundationModelAvailability(locale: nil, useCase: request.useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let session = LanguageModelSession(
    model: foundationModel(useCase: request.useCase),
    instructions: request.instructions
  )
  session.prewarm(promptPrefix: request.promptPrefix.map(Prompt.init))
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelStringResponse(
  for request: FoundationModelGenerationRequest
) async throws -> FoundationModelGenerationResponse<String> {
  try await foundationModelResponse(for: request) { session, options in
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
  for request: FoundationModelGenerationRequest
) async throws -> FoundationModelGenerationResponse<Content> {
  try await foundationModelResponse(for: request) { session, options in
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
  perform: (LanguageModelSession, GenerationOptions) async throws -> Content
) async throws -> FoundationModelGenerationResponse<Content> {
  let availability = foundationModelAvailability(locale: nil, useCase: request.useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let model = foundationModel(useCase: request.useCase)
  let session = LanguageModelSession(
    model: model,
    instructions: request.prompt.systemInstructions
  )
  if let prewarmPromptPrefix = request.prewarmPromptPrefix {
    session.prewarm(promptPrefix: Prompt(prewarmPromptPrefix))
  }

  let startedAt = Date()
  let options = request.options.foundationGenerationOptions
  let estimatedInputTokens = TokenCounter.latinHeuristic.count(
    request.prompt.systemInstructions + "\n\n" + request.prompt.userPrompt
  )
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
private func foundationModelFailure(
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
