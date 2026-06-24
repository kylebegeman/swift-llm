import Foundation

/// A sequential, typed workflow for deterministic analysis, local retrieval,
/// prompt planning, generation, validation, and fallback.
public struct LLMWorkflow<Input: Sendable, Output: Sendable>: Sendable {
  private var runHandler:
    @Sendable (Input, LLMWorkflowContext) async throws -> (Output, LLMWorkflowContext)

  public init(_ step: LLMStep<Input, Output>) {
    self.runHandler = { input, context in
      try await step.execute(input, context: context)
    }
  }

  public init(step: LLMStep<Input, Output>) {
    self.init(step)
  }

  private init(
    run: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> (Output, LLMWorkflowContext)
  ) {
    self.runHandler = run
  }

  public func then<NextOutput: Sendable>(
    _ step: LLMStep<Output, NextOutput>
  ) -> LLMWorkflow<Input, NextOutput> {
    LLMWorkflow<Input, NextOutput> { input, context in
      let (output, nextContext) = try await runHandler(input, context)
      return try await step.execute(output, context: nextContext)
    }
  }

  public func run(
    _ input: Input,
    options: LLMWorkflowOptions = .default,
    context: LLMWorkflowContext = LLMWorkflowContext()
  ) async throws -> LLMWorkflowResult<Output> {
    var context = context
    context.options = options
    try Task.checkCancellation()
    let (output, finalContext) = try await runHandler(input, context)
    try Task.checkCancellation()
    return finalContext.result(output: output)
  }
}

extension LLMWorkflowContext {
  mutating func apply<Output: Sendable>(
    _ result: LLMStepResult<Output>,
    from step: LLMStep<some Sendable, Output>
  ) {
    appendEvents(result.events)

    if options.captureIntermediateOutputs,
      let intermediateOutput = result.intermediateOutput
    {
      intermediateOutputs.append(intermediateOutput)
    }

    if let contextPlan = result.contextPlan {
      self.contextPlan = contextPlan
    }
    if let sourceContext = result.sourceContext {
      mergeSourceContext(sourceContext)
    }
    if let fallbackReason = result.fallbackReason {
      self.fallbackReason = fallbackReason
    }

    providerMetadata.appendUnique(contentsOf: result.providerMetadata)
    tokenUsage.append(contentsOf: result.tokenUsage)
    budgetReports.append(contentsOf: result.budgetReports)
    validationIssues.appendUnique(contentsOf: result.validationIssues, by: \.id)
    evidence.appendUnique(contentsOf: result.evidence, by: \.id)
    sourceReferences.appendUnique(contentsOf: result.sourceReferences, by: \.id)
    retrievalResults.append(contentsOf: result.retrievalResults)

    if result.fallbackReason != nil {
      metadata["lastFallbackStepID"] = step.id
    }
  }

  mutating func appendEvent(_ event: LLMWorkflowEvent) {
    guard options.captureEvents else { return }
    var event = event
    event.sequence = events.count
    events.append(event)
  }

  mutating func appendEvents(_ events: [LLMWorkflowEvent]) {
    for event in events {
      appendEvent(event)
    }
  }

  mutating func mergeSourceContext(_ newContext: StructuredGenerationSourceContext) {
    var sources = sourceContext.sources
    sources.appendUnique(contentsOf: newContext.sources, by: \.id)
    sourceContext = StructuredGenerationSourceContext(sources: sources)
  }

  func result<Output: Sendable>(output: Output) -> LLMWorkflowResult<Output> {
    LLMWorkflowResult(
      output: output,
      intermediateOutputs: intermediateOutputs,
      providerMetadata: providerMetadata,
      budgetReport: LLMWorkflowBudgetReport(
        contextReports: budgetReports,
        tokenUsage: tokenUsage
      ),
      fallbackReason: fallbackReason,
      validationIssues: validationIssues,
      evidence: evidence,
      sourceReferences: sourceReferences,
      retrievalResults: retrievalResults,
      contextPlan: contextPlan,
      events: events
    )
  }
}

extension LLMStepKind {
  var diagnosticName: String {
    switch self {
    case .contextPlanning:
      return "contextPlanning"
    case let .custom(name):
      return name
    case .deterministic:
      return "deterministic"
    case .generation:
      return "generation"
    case .repairFallback:
      return "repairFallback"
    case .retrieval:
      return "retrieval"
    case .validation:
      return "validation"
    }
  }
}

private extension Array {
  mutating func appendUnique(
    contentsOf newElements: [Element]
  ) where Element: Equatable {
    for element in newElements where !contains(element) {
      append(element)
    }
  }

  mutating func appendUnique<ID: Hashable>(
    contentsOf newElements: [Element],
    by id: (Element) -> ID
  ) {
    var seenIDs = Set(map(id))
    for element in newElements {
      let elementID = id(element)
      guard !seenIDs.contains(elementID) else { continue }
      seenIDs.insert(elementID)
      append(element)
    }
  }
}
