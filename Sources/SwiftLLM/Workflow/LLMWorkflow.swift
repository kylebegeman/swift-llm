import Foundation

/// Runtime options for a workflow run.
public struct LLMWorkflowOptions: Equatable, Sendable {
  public var captureEvents: Bool
  public var captureIntermediateOutputs: Bool

  public init(
    captureIntermediateOutputs: Bool = false,
    captureEvents: Bool = true
  ) {
    self.captureEvents = captureEvents
    self.captureIntermediateOutputs = captureIntermediateOutputs
  }

  public static let `default` = Self()
}

/// The broad role a step plays in a workflow.
public enum LLMStepKind: Equatable, Sendable {
  case contextPlanning
  case custom(String)
  case deterministic
  case generation
  case repairFallback
  case retrieval
  case validation
}

/// A compact, type-erased representation of an intermediate step output.
public enum LLMWorkflowOutputPayload: Equatable, Sendable {
  case json(JSONValue)
  case redacted(String)
  case references([String])
  case text(String)
}

/// A captured intermediate output. Workflows only keep these when
/// `LLMWorkflowOptions.captureIntermediateOutputs` is enabled.
public struct LLMWorkflowIntermediateOutput: Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var metadata: [String: String]
  public var payload: LLMWorkflowOutputPayload
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    label: String,
    payload: LLMWorkflowOutputPayload,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.label = label
    self.metadata = metadata
    self.payload = payload
    self.stepID = stepID
  }
}

public enum LLMWorkflowEventKind: String, Equatable, Sendable {
  case contextPlanned
  case fallbackApplied
  case generationCompleted
  case retrievalCompleted
  case stepFinished
  case stepStarted
  case validationCompleted
}

/// A deterministic event emitted by workflow orchestration.
public struct LLMWorkflowEvent: Equatable, Identifiable, Sendable {
  public var fallbackReason: FallbackReason?
  public var kind: LLMWorkflowEventKind
  public var message: String?
  public var metadata: [String: String]
  public var sequence: Int
  public var stepID: String?

  public var id: Int { sequence }

  public init(
    sequence: Int = 0,
    kind: LLMWorkflowEventKind,
    stepID: String? = nil,
    message: String? = nil,
    metadata: [String: String] = [:],
    fallbackReason: FallbackReason? = nil
  ) {
    self.fallbackReason = fallbackReason
    self.kind = kind
    self.message = message
    self.metadata = metadata
    self.sequence = sequence
    self.stepID = stepID
  }
}

public struct LLMWorkflowContextBudgetReport: Equatable, Identifiable, Sendable {
  public var id: String
  public var report: LLMContextBudgetReport
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    report: LLMContextBudgetReport
  ) {
    self.id = id
    self.report = report
    self.stepID = stepID
  }
}

public struct LLMWorkflowBudgetReport: Equatable, Sendable {
  public var contextReports: [LLMWorkflowContextBudgetReport]
  public var tokenUsage: [LLMTokenUsage]

  public init(
    contextReports: [LLMWorkflowContextBudgetReport] = [],
    tokenUsage: [LLMTokenUsage] = []
  ) {
    self.contextReports = contextReports
    self.tokenUsage = tokenUsage
  }

  public var estimatedInputTokens: Int {
    tokenUsage.reduce(0) { $0 + $1.estimatedInputTokens }
  }

  public var estimatedOutputTokens: Int {
    tokenUsage.reduce(0) { $0 + $1.estimatedOutputTokens }
  }

  public var measuredInputTokens: Int? {
    sumMeasured(\.measuredInputTokens)
  }

  public var measuredOutputTokens: Int? {
    sumMeasured(\.measuredOutputTokens)
  }

  public var exceedsContextBudget: Bool {
    contextReports.contains { $0.report.exceedsBudget }
  }

  private func sumMeasured(_ keyPath: KeyPath<LLMTokenUsage, Int?>) -> Int? {
    var total = 0
    for usage in tokenUsage {
      guard let value = usage[keyPath: keyPath] else { return nil }
      total += value
    }
    return total
  }
}

/// Accumulated workflow state that steps can inspect when building prompts,
/// retrieval queries, validators, and fallback output.
public struct LLMWorkflowContext: Sendable {
  public var budget: TokenBudget
  public var budgetReports: [LLMWorkflowContextBudgetReport]
  public var contextPlan: LLMContextPlan?
  public var counter: TokenCounter
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LLMWorkflowIntermediateOutput]
  public var metadata: [String: String]
  public var options: LLMWorkflowOptions
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LLMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    options: LLMWorkflowOptions = .default,
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic,
    contextPlan: LLMContextPlan? = nil,
    sourceContext: StructuredGenerationSourceContext = StructuredGenerationSourceContext(),
    metadata: [String: String] = [:],
    events: [LLMWorkflowEvent] = [],
    intermediateOutputs: [LLMWorkflowIntermediateOutput] = [],
    providerMetadata: [LLMProviderMetadata] = [],
    tokenUsage: [LLMTokenUsage] = [],
    budgetReports: [LLMWorkflowContextBudgetReport] = [],
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = []
  ) {
    self.budget = budget
    self.budgetReports = budgetReports
    self.contextPlan = contextPlan
    self.counter = counter
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutputs = intermediateOutputs
    self.metadata = metadata
    self.options = options
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceContext = sourceContext
    self.sourceReferences = sourceReferences
    self.tokenUsage = tokenUsage
    self.validationIssues = validationIssues
  }
}

/// The final output and diagnostics from a workflow run.
public struct LLMWorkflowResult<Output: Sendable>: Sendable {
  public var budgetReport: LLMWorkflowBudgetReport
  public var contextPlan: LLMContextPlan?
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LLMWorkflowIntermediateOutput]
  public var output: Output
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceReferences: [SourceReference]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    intermediateOutputs: [LLMWorkflowIntermediateOutput] = [],
    providerMetadata: [LLMProviderMetadata] = [],
    budgetReport: LLMWorkflowBudgetReport = LLMWorkflowBudgetReport(),
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = [],
    contextPlan: LLMContextPlan? = nil,
    events: [LLMWorkflowEvent] = []
  ) {
    self.budgetReport = budgetReport
    self.contextPlan = contextPlan
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutputs = intermediateOutputs
    self.output = output
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceReferences = sourceReferences
    self.validationIssues = validationIssues
  }
}

extension LLMWorkflowResult: Equatable where Output: Equatable {}

/// A typed result emitted by one workflow step.
public struct LLMStepResult<Output: Sendable>: Sendable {
  public var budgetReports: [LLMWorkflowContextBudgetReport]
  public var contextPlan: LLMContextPlan?
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutput: LLMWorkflowIntermediateOutput?
  public var output: Output
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext?
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LLMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    events: [LLMWorkflowEvent] = [],
    intermediateOutput: LLMWorkflowIntermediateOutput? = nil,
    providerMetadata: [LLMProviderMetadata] = [],
    tokenUsage: [LLMTokenUsage] = [],
    contextPlan: LLMContextPlan? = nil,
    budgetReports: [LLMWorkflowContextBudgetReport] = [],
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = [],
    sourceContext: StructuredGenerationSourceContext? = nil
  ) {
    self.budgetReports = budgetReports
    self.contextPlan = contextPlan
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutput = intermediateOutput
    self.output = output
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceContext = sourceContext
    self.sourceReferences = sourceReferences
    self.tokenUsage = tokenUsage
    self.validationIssues = validationIssues
  }
}

/// A typed, composable unit of work. Steps may transform the typed value and
/// may also add workflow diagnostics such as provenance, validation issues, and
/// token reports.
public struct LLMStep<Input: Sendable, Output: Sendable>: Sendable {
  public var id: String
  public var kind: LLMStepKind
  private var operation:
    @Sendable (Input, LLMWorkflowContext) async throws -> LLMStepResult<Output>

  public init(
    id: String,
    kind: LLMStepKind,
    operation: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> LLMStepResult<Output>
  ) {
    self.id = id
    self.kind = kind
    self.operation = operation
  }

  public func run(
    _ input: Input,
    context: LLMWorkflowContext
  ) async throws -> LLMStepResult<Output> {
    try await operation(input, context)
  }

  fileprivate func execute(
    _ input: Input,
    context: LLMWorkflowContext
  ) async throws -> (Output, LLMWorkflowContext) {
    var context = context
    context.appendEvent(
      LLMWorkflowEvent(
        kind: .stepStarted,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    try Task.checkCancellation()
    let result = try await operation(input, context)
    try Task.checkCancellation()

    context.apply(result, from: self)
    context.appendEvent(
      LLMWorkflowEvent(
        kind: .stepFinished,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    return (result.output, context)
  }
}

extension LLMStep {
  /// Build a deterministic transform or analysis step.
  public static func deterministicTransform(
    id: String,
    captureIntermediateOutput: (@Sendable (Output) -> LLMWorkflowIntermediateOutput?)? = nil,
    transform: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> Output
  ) -> Self {
    Self(id: id, kind: .deterministic) { input, context in
      let output = try await transform(input, context)
      return LLMStepResult(
        output: output,
        intermediateOutput: captureIntermediateOutput?(output)
      )
    }
  }
}

extension LLMStep where Output == Input {
  /// Run local retrieval and context packing while passing the typed input through.
  public static func localRetrieval(
    id: String,
    pipeline: LocalRAGPipeline,
    query: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> LocalRetrievalQuery
  ) -> Self {
    Self(id: id, kind: .retrieval) { input, context in
      let result = try await pipeline.run(query: try await query(input, context))
      let contextItem = LLMContextItem(
        id: "\(id)-retrieved-context",
        surface: .retrievedContext,
        text: result.contextBlock,
        trust: .trustedApp,
        estimatedTokens: context.counter.count(result.contextBlock)
      )
      let plan = LLMContextPlan(items: [contextItem])
      let budgetReport = LLMWorkflowContextBudgetReport(
        id: "\(id)-budget",
        stepID: id,
        report: plan.budgetReport(budget: context.budget, counter: context.counter)
      )
      let evidence = result.packedSnippets.map { snippet in
        EvidenceSpan(
          id: snippet.id,
          text: snippet.text,
          sourceID: snippet.id,
          characterRange: snippet.characterRange
        )
      }

      return LLMStepResult(
        output: input,
        events: [
          LLMWorkflowEvent(
            kind: .retrievalCompleted,
            stepID: id,
            metadata: [
              "packedSnippetCount": "\(result.packedSnippets.count)",
              "retrievedSnippetCount": "\(result.retrieval.snippets.count)",
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-context",
          stepID: id,
          label: "Retrieved context",
          payload: .references(result.packedSnippets.map(\.id))
        ),
        budgetReports: [budgetReport],
        evidence: evidence,
        sourceReferences: result.retrieval.sources,
        retrievalResults: [result],
        sourceContext: result.sourceContext
      )
    }
  }
}

extension LLMStep where Output == CompiledPrompt {
  /// Build a compiled prompt and record its context plan and provider metadata.
  public static func contextPlanning(
    id: String,
    build: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> CompiledPrompt
  ) -> Self {
    Self(id: id, kind: .contextPlanning) { input, context in
      let prompt = try await build(input, context)
      let budgetReport = prompt.contextPlan.map { plan in
        LLMWorkflowContextBudgetReport(
          id: "\(id)-budget",
          stepID: id,
          report: plan.budgetReport(budget: context.budget, counter: context.counter)
        )
      }

      return LLMStepResult(
        output: prompt,
        events: [
          LLMWorkflowEvent(
            kind: .contextPlanned,
            stepID: id,
            metadata: [
              "contextItemCount": "\(prompt.contextPlan?.items.count ?? 0)",
              "promptID": prompt.contract.id,
              "promptVersion": prompt.contract.version,
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-compiled-prompt",
          stepID: id,
          label: "Compiled prompt",
          payload: .json([
            "contextItemCount": .number(Double(prompt.contextPlan?.items.count ?? 0)),
            "promptID": .string(prompt.contract.id),
            "promptVersion": .string(prompt.contract.version),
          ])
        ),
        providerMetadata: [prompt.metadata],
        contextPlan: prompt.contextPlan,
        budgetReports: budgetReport.map { [$0] } ?? []
      )
    }
  }
}

extension LLMStep {
  /// Run app-supplied generation and wrap the output in a structured candidate.
  public static func modelGeneration<Generated: Sendable>(
    id: String,
    generate: @escaping @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Generated>,
    evidence: @escaping @Sendable (
      Generated,
      LLMWorkflowContext
    ) -> [EvidenceSpan] = { _, _ in [] },
    rawOutputDescription: @escaping @Sendable (Generated) -> String? = {
      String(describing: $0)
    }
  ) -> LLMStep<CompiledPrompt, StructuredGenerationCandidate<Generated>> {
    LLMStep<CompiledPrompt, StructuredGenerationCandidate<Generated>>(
      id: id,
      kind: .generation
    ) { prompt, context in
      let generated = try await generate(prompt)
      let candidate = StructuredGenerationCandidate(
        generationCandidate: generated,
        evidence: evidence(generated.output, context),
        rawOutputDescription: rawOutputDescription(generated.output)
      )

      return LLMStepResult(
        output: candidate,
        events: [
          LLMWorkflowEvent(
            kind: .generationCompleted,
            stepID: id,
            metadata: [
              "provider": candidate.metadata.providerDisplayName,
              "providerKind": candidate.metadata.providerKind.rawValue,
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-candidate",
          stepID: id,
          label: "Generated candidate",
          payload: .redacted("Structured generation candidate")
        ),
        providerMetadata: [candidate.metadata],
        tokenUsage: candidate.tokenUsage.map { [$0] } ?? [],
        evidence: candidate.evidence
      )
    }
  }

  /// Validate a structured generation candidate against the accumulated source context.
  public static func structuredValidation<Generated: Sendable>(
    id: String,
    validator: StructuredGenerationValidator<Generated>,
    sourceContext: @escaping @Sendable (
      StructuredGenerationCandidate<Generated>,
      LLMWorkflowContext
    ) -> StructuredGenerationSourceContext = { _, context in context.sourceContext }
  ) -> LLMStep<
    StructuredGenerationCandidate<Generated>,
    StructuredGenerationPipelineResult<Generated>
  > {
    LLMStep<
      StructuredGenerationCandidate<Generated>,
      StructuredGenerationPipelineResult<Generated>
    >(id: id, kind: .validation) { candidate, context in
      let validation = validator(candidate, in: sourceContext(candidate, context))
      let status: StructuredGenerationPipelineStatus = validation.isAccepted
        ? .accepted
        : .rejected
      let result = StructuredGenerationPipelineResult(
        status: status,
        candidate: candidate,
        validation: validation
      )

      return LLMStepResult(
        output: result,
        events: [
          LLMWorkflowEvent(
            kind: .validationCompleted,
            stepID: id,
            metadata: [
              "accepted": "\(validation.isAccepted)",
              "issueCount": "\(validation.issues.count)",
            ]
          )
        ],
        validationIssues: validation.issues,
        evidence: candidate.evidence
      )
    }
  }

  /// Convert validation/generation pipeline status into final output, using a
  /// deterministic fallback when the supplied policy can resolve one.
  public static func repairOrFallback<Generated: Sendable>(
    id: String,
    repairPolicy: StructuredGenerationRepairPolicy<Generated> = .none,
    fallbackPolicy: StructuredGenerationFallbackPolicy<Generated> = .none
  ) -> LLMStep<StructuredGenerationPipelineResult<Generated>, Generated> {
    LLMStep<StructuredGenerationPipelineResult<Generated>, Generated>(
      id: id,
      kind: .repairFallback
    ) { result, _ in
      if let output = result.output,
        result.status == .accepted
      {
        return LLMStepResult(output: output)
      }

      if let fallbackDecision = result.fallbackDecision,
        let output = fallbackDecision.output
      {
        return LLMStepResult(
          output: output,
          events: [
            LLMWorkflowEvent(
              kind: .fallbackApplied,
              stepID: id,
              fallbackReason: fallbackDecision.reason
            )
          ],
          fallbackReason: fallbackDecision.reason,
          validationIssues: result.validation.issues
        )
      }

      let reason: FallbackReason = result.status == .failed
        ? .providerError(result.errorMessage ?? "Generation failed.")
        : .validationFailed
      let repairPlan = repairPolicy.plan(result.candidate, result.validation, reason)
      let plannedReason: FallbackReason
      switch repairPlan.action {
      case let .fallback(reason):
        plannedReason = reason
      case .none,
          .retryWithFewerExamples,
          .retryWithMaximumResponseTokens,
          .retryWithShorterContext,
          .retryWithSimplerSchema:
        plannedReason = reason
      }

      if let output = fallbackPolicy.resolve(
        plannedReason,
        result.candidate,
        result.validation
      ) {
        return LLMStepResult(
          output: output,
          events: [
            LLMWorkflowEvent(
              kind: .fallbackApplied,
              stepID: id,
              fallbackReason: plannedReason
            )
          ],
          fallbackReason: plannedReason,
          validationIssues: result.validation.issues,
          evidence: result.candidate?.evidence ?? []
        )
      }

      if let output = result.output {
        return LLMStepResult(
          output: output,
          validationIssues: result.validation.issues,
          evidence: result.candidate?.evidence ?? []
        )
      }

      throw LLMError("Workflow step \(id) could not repair or fall back.")
    }
  }
}

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

private extension LLMWorkflowContext {
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

private extension LLMStepKind {
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
