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
  public var runReceiptHandler: (@Sendable (LLMRunReceipt) -> Void)?
  public var streamFallbackMode: LLMStreamFallbackMode

  public init(
    primary: AnyLLMClient,
    fallbacks: [AnyLLMClient] = [],
    fallbackPolicy: LLMRouterFallbackPolicy = .retryable,
    runReceiptHandler: (@Sendable (LLMRunReceipt) -> Void)? = nil,
    streamFallbackMode: LLMStreamFallbackMode = .beforeFirstOutput
  ) {
    self.fallbacks = fallbacks
    self.fallbackPolicy = fallbackPolicy
    self.primary = primary
    self.runReceiptHandler = runReceiptHandler
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
    do {
      let result = try await respondWithReceipt(to: request)
      runReceiptHandler?(result.receipt)
      return result.response
    } catch let error as LLMRunReceiptError {
      runReceiptHandler?(error.receipt)
      throw error.underlyingError
    }
  }

  public func respondWithReceipt(to request: LLMRequest) async throws -> LLMInstrumentedResponse {
    var lastError: (any Error)?
    let clients = configuredClients
    let runID = UUID().uuidString
    let runStartedAt = Date()
    var receipt = LLMRunReceipt(
      id: runID,
      request: LLMRunRequestSummary(request: request),
      startedAt: runStartedAt
    )

    for (index, client) in clients.enumerated() {
      let remainingFallbackCount = clients.count - index - 1
      let context = fallbackContext(
        client: client,
        request: request,
        attemptIndex: index,
        remainingFallbackCount: remainingFallbackCount
      )
      let unsupportedCapabilities = client.capabilities.unsupportedCapabilities(
        for: request,
        streaming: false
      )
      if !unsupportedCapabilities.isEmpty {
        let unsupportedError = unsupportedCapabilitiesError(
          for: request,
          client: client,
          streaming: false
        ) ?? LLMClientError(reason: .unsupported)
        lastError = unsupportedError
        let attemptedAt = Date()
        receipt.attempts.append(
          LLMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LLMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: Date(),
            status: .skippedUnsupportedCapabilities,
            unsupportedCapabilities: unsupportedCapabilities.map(\.rawValue).sorted(),
            error: LLMRunErrorReceipt(error: unsupportedError)
          )
        )
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(unsupportedError, context)
        else {
          receipt.completedAt = Date()
          receipt.outcome = .failed
          throw LLMRunReceiptError(underlyingError: unsupportedError, receipt: receipt)
        }
        continue
      }

      let attemptedAt = Date()
      do {
        let response = try await client.respond(to: request)
        let completedAt = Date()
        receipt.attempts.append(
          LLMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LLMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: completedAt,
            status: .succeeded,
            tokenUsage: response.tokenUsage.map(LLMTokenUsageReceipt.init)
          )
        )
        receipt.completedAt = completedAt
        receipt.finalProvider = LLMProviderReceiptSnapshot(metadata: response.metadata)
        receipt.outcome = .succeeded
        receipt.tokenUsage = response.tokenUsage.map(LLMTokenUsageReceipt.init)
        return LLMInstrumentedResponse(response: response, receipt: receipt)
      } catch {
        lastError = error
        receipt.attempts.append(
          LLMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LLMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: Date(),
            status: .failed,
            error: LLMRunErrorReceipt(error: error)
          )
        )
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(error, context)
        else {
          receipt.completedAt = Date()
          receipt.outcome = .failed
          throw LLMRunReceiptError(underlyingError: error, receipt: receipt)
        }
      }
    }

    let error = lastError ?? Self.noProvidersError
    receipt.completedAt = Date()
    receipt.outcome = .failed
    throw LLMRunReceiptError(underlyingError: error, receipt: receipt)
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
  public var contextCompilation: LLMContextCompilationResult?
  public var ragResult: LocalRAGResult?
  public var request: LLMRequest
  public var response: LLMResponse

  public init(
    compiledPrompt: CompiledPrompt,
    request: LLMRequest,
    response: LLMResponse,
    ragResult: LocalRAGResult? = nil,
    contextCompilation: LLMContextCompilationResult? = nil
  ) {
    self.compiledPrompt = compiledPrompt
    self.contextCompilation = contextCompilation
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
    var retrieval: LocalRetrievalResult?
    var retrievalQuery: LocalRetrievalQuery?
    if let query = task.retrievalQuery?(input),
       let ragPipeline
    {
      retrievalQuery = query
      retrieval = try await ragPipeline.retriever.retrieve(query)
    }

    let compiler = LLMContextCompiler(
      budget: ragPipeline?.packer.budget ?? TokenBudget(),
      packingStrategy: ragPipeline?.packer.strategy ?? .scoreDescending,
      renderer: ragPipeline?.renderer ?? CitationContextRenderer(),
      additionalReservedInputTokens: ragPipeline?.reservedInputTokens ?? 0
    )
    let contextCompilation = compiler.compile(
      LLMContextCompilationInput(
        contract: task.contract,
        metadata: metadata,
        userPrompt: input,
        examples: task.exampleSelector.select(from: task.examples),
        retrievedSnippets: retrieval?.snippets ?? [],
        tools: task.tools
      )
    )
    let compiledPrompt = contextCompilation.compiledPrompt
    if let retrievalQuery,
       let retrieval
    {
      ragResult = LocalRAGResult(
        query: retrievalQuery,
        retrieval: retrieval,
        packedSnippets: contextCompilation.packedSnippets,
        contextBlock: contextCompilation.contextBlock,
        citations: contextCompilation.citations
      )
    }
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
      ragResult: ragResult,
      contextCompilation: contextCompilation
    )
  }
}
