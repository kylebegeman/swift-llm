import Foundation

public struct LLMRouter: LLMClient {
  public var fallbacks: [AnyLLMClient]
  public var primary: AnyLLMClient

  public init(
    primary: AnyLLMClient,
    fallbacks: [AnyLLMClient] = []
  ) {
    self.fallbacks = fallbacks
    self.primary = primary
  }

  public var metadata: LLMProviderMetadata {
    primary.metadata
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    var lastError: (any Error)?

    for client in [primary] + fallbacks {
      do {
        return try await client.respond(to: request)
      } catch {
        lastError = error
      }
    }

    throw lastError ?? LLMClientError(
      reason: .unavailable,
      debugDescription: "No providers were configured."
    )
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    primary.stream(to: request)
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
