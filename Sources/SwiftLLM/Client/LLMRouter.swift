import Foundation

public struct LLMRouterFallbackContext: Sendable {
  public var attemptIndex: Int
  public var client: LLMProviderMetadata
  public var remainingFallbackCount: Int
  public var request: LLMRequest

  public init(
    attemptIndex: Int,
    client: LLMProviderMetadata,
    remainingFallbackCount: Int,
    request: LLMRequest
  ) {
    self.attemptIndex = attemptIndex
    self.client = client
    self.remainingFallbackCount = remainingFallbackCount
    self.request = request
  }
}

public struct LLMRouterFallbackPolicy: Sendable {
  public var shouldAttemptFallback: @Sendable (any Error, LLMRouterFallbackContext) -> Bool

  public init(
    shouldAttemptFallback: @escaping @Sendable (any Error, LLMRouterFallbackContext) -> Bool
  ) {
    self.shouldAttemptFallback = shouldAttemptFallback
  }

  public static let retryable = Self { error, _ in
    let fallbackReason = (error as? any LLMFallbackClassifiableError)?.fallbackReason
    switch fallbackReason {
    case .assetsUnavailable,
      .concurrentRequest,
      .contextExceeded,
      .rateLimited,
      .unavailable,
      .unsupported,
      .unsupportedGuide,
      .unsupportedLocale:
      return true
    case .decodingFailed,
      .guardrailViolation,
      .providerError,
      .refusal,
      .validationFailed,
      nil:
      return false
    }
  }

  public static let always = Self { _, _ in true }

  public static let never = Self { _, _ in false }
}

public enum LLMStreamFallbackMode: Equatable, Sendable {
  case beforeFirstOutput
  case disabled
}

public struct LLMRouter: LLMClient {
  public var fallbacks: [AnyLLMClient]
  public var fallbackPolicy: LLMRouterFallbackPolicy
  public var primary: AnyLLMClient
  public var streamFallbackMode: LLMStreamFallbackMode

  public init(
    primary: AnyLLMClient,
    fallbacks: [AnyLLMClient] = [],
    fallbackPolicy: LLMRouterFallbackPolicy = .retryable,
    streamFallbackMode: LLMStreamFallbackMode = .beforeFirstOutput
  ) {
    self.fallbacks = fallbacks
    self.fallbackPolicy = fallbackPolicy
    self.primary = primary
    self.streamFallbackMode = streamFallbackMode
  }

  public var capabilities: LLMClientCapabilities {
    let clients = configuredClients
    guard var merged = clients.first?.capabilities else {
      return .broadlyCompatible
    }
    for client in clients.dropFirst() {
      merged.supportedFeatures.formUnion(client.capabilities.supportedFeatures)
      if let current = merged.contextWindowTokens,
         let candidate = client.capabilities.contextWindowTokens
      {
        merged.contextWindowTokens = max(current, candidate)
      } else {
        merged.contextWindowTokens = merged.contextWindowTokens ?? client.capabilities.contextWindowTokens
      }
    }
    return merged
  }

  public var metadata: LLMProviderMetadata {
    primary.metadata
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    var lastError: (any Error)?
    let clients = configuredClients

    for (index, client) in clients.enumerated() {
      let remainingFallbackCount = clients.count - index - 1
      let context = fallbackContext(
        client: client,
        request: request,
        attemptIndex: index,
        remainingFallbackCount: remainingFallbackCount
      )
      let unsupportedError = unsupportedCapabilitiesError(
        for: request,
        client: client,
        streaming: false
      )
      if let unsupportedError {
        lastError = unsupportedError
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(unsupportedError, context)
        else { throw unsupportedError }
        continue
      }

      do {
        return try await client.respond(to: request)
      } catch {
        lastError = error
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(error, context)
        else { throw error }
      }
    }

    throw lastError ?? Self.noProvidersError
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let clients = configuredClients
        var lastError: (any Error)?

        for (index, client) in clients.enumerated() {
          let remainingFallbackCount = clients.count - index - 1
          let context = fallbackContext(
            client: client,
            request: request,
            attemptIndex: index,
            remainingFallbackCount: remainingFallbackCount
          )
          let unsupportedError = unsupportedCapabilitiesError(
            for: request,
            client: client,
            streaming: true
          )
          if let unsupportedError {
            lastError = unsupportedError
            guard shouldAttemptStreamFallback(
              after: unsupportedError,
              context: context,
              remainingFallbackCount: remainingFallbackCount,
              emittedOutput: false
            )
            else {
              continuation.finish(throwing: unsupportedError)
              return
            }
            continue
          }

          var emittedOutput = false
          do {
            for try await event in client.stream(to: request) {
              if event.isOutput {
                emittedOutput = true
              }
              continuation.yield(event)
            }
            continuation.finish()
            return
          } catch {
            lastError = error
            guard shouldAttemptStreamFallback(
              after: error,
              context: context,
              remainingFallbackCount: remainingFallbackCount,
              emittedOutput: emittedOutput
            )
            else {
              continuation.finish(throwing: error)
              return
            }
          }
        }

        continuation.finish(throwing: lastError ?? Self.noProvidersError)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private var configuredClients: [AnyLLMClient] {
    [primary] + fallbacks
  }

  private static var noProvidersError: LLMClientError {
    LLMClientError(
      reason: .unavailable,
      debugDescription: "No providers were configured."
    )
  }

  private func fallbackContext(
    client: AnyLLMClient,
    request: LLMRequest,
    attemptIndex: Int,
    remainingFallbackCount: Int
  ) -> LLMRouterFallbackContext {
    LLMRouterFallbackContext(
      attemptIndex: attemptIndex,
      client: client.metadata,
      remainingFallbackCount: remainingFallbackCount,
      request: request
    )
  }

  private func shouldAttemptStreamFallback(
    after error: any Error,
    context: LLMRouterFallbackContext,
    remainingFallbackCount: Int,
    emittedOutput: Bool
  ) -> Bool {
    guard streamFallbackMode == .beforeFirstOutput,
          !emittedOutput,
          remainingFallbackCount > 0
    else { return false }

    return fallbackPolicy.shouldAttemptFallback(error, context)
  }

  private func unsupportedCapabilitiesError(
    for request: LLMRequest,
    client: AnyLLMClient,
    streaming: Bool
  ) -> LLMClientError? {
    let unsupportedCapabilities = client.capabilities.unsupportedCapabilities(
      for: request,
      streaming: streaming
    )
    guard !unsupportedCapabilities.isEmpty else { return nil }

    return LLMClientError(
      reason: .unsupported,
      debugDescription: """
      \(client.metadata.providerDisplayName) does not support required capabilities: \
      \(unsupportedCapabilities.map(\.rawValue).joined(separator: ", ")).
      """
    )
  }
}

private extension LLMStreamEvent {
  var isOutput: Bool {
    switch self {
    case .completed, .textDelta, .toolCall:
      return true
    case .started:
      return false
    }
  }
}

public struct LLMPromptTask: Sendable {
  public var contract: PromptContract
  public var examples: [PromptExample]
  public var exampleSelector: ExampleSelector
  public var parameters: LLMGenerationParameters
  public var responseFormat: LLMResponseFormat
  public var retrievalQuery: (@Sendable (String) -> LocalRetrievalQuery?)?
  public var toolChoice: LLMToolChoice?
  public var tools: [LLMToolDefinition]

  public init(
    contract: PromptContract,
    examples: [PromptExample] = [],
    exampleSelector: ExampleSelector = ExampleSelector(),
    responseFormat: LLMResponseFormat = .text,
    tools: [LLMToolDefinition] = [],
    toolChoice: LLMToolChoice? = nil,
    parameters: LLMGenerationParameters = LLMGenerationParameters(),
    retrievalQuery: (@Sendable (String) -> LocalRetrievalQuery?)? = nil
  ) {
    self.contract = contract
    self.examples = examples
    self.exampleSelector = exampleSelector
    self.parameters = parameters
    self.responseFormat = responseFormat
    self.retrievalQuery = retrievalQuery
    self.toolChoice = toolChoice
    self.tools = tools
  }
}

public struct LLMPipelineResult: Sendable {
  public var compiledPrompt: CompiledPrompt
  public var ragResult: LocalRAGResult?
  public var request: LLMRequest
  public var response: LLMResponse

  public init(
    compiledPrompt: CompiledPrompt,
    request: LLMRequest,
    response: LLMResponse,
    ragResult: LocalRAGResult? = nil
  ) {
    self.compiledPrompt = compiledPrompt
    self.ragResult = ragResult
    self.request = request
    self.response = response
  }
}

public struct LLMPipeline: Sendable {
  public var client: AnyLLMClient
  public var ragPipeline: LocalRAGPipeline?

  public init(
    client: AnyLLMClient,
    ragPipeline: LocalRAGPipeline? = nil
  ) {
    self.client = client
    self.ragPipeline = ragPipeline
  }

  public func run(
    task: LLMPromptTask,
    input: String
  ) async throws -> LLMPipelineResult {
    var metadata = client.metadata
    metadata.promptVersion = task.contract.version

    var ragResult: LocalRAGResult?
    var userPrompt = input
    if let retrievalQuery = task.retrievalQuery?(input),
       let ragPipeline
    {
      let result = try await ragPipeline.run(query: retrievalQuery)
      ragResult = result
      if !result.contextBlock.isEmpty {
        userPrompt = Self.prompt(
          input: input,
          retrievedContext: result.contextBlock
        )
      }
    }

    let compiledPrompt = CompiledPrompt(
      contract: task.contract,
      examples: task.exampleSelector.select(from: task.examples),
      metadata: metadata,
      userPrompt: userPrompt
    )
    let request = LLMRequest(
      prompt: compiledPrompt,
      responseFormat: task.responseFormat,
      tools: task.tools,
      toolChoice: task.toolChoice,
      parameters: task.parameters,
      metadata: ragResult.map { ["retrievalSnippetCount": "\($0.packedSnippets.count)"] } ?? [:]
    )
    let response = try await client.respond(to: request)

    return LLMPipelineResult(
      compiledPrompt: compiledPrompt,
      request: request,
      response: response,
      ragResult: ragResult
    )
  }

  private static func prompt(
    input: String,
    retrievedContext: String
  ) -> String {
    """
    User input:
    \(input)

    Retrieved context:
    \(retrievedContext)
    """
  }
}
