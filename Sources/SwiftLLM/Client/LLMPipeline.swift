import Foundation

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
