import Foundation
import SwiftLLM
import Testing

@Suite("Workflow orchestration")
struct WorkflowTests {
  @Test
  func successfulWorkflowPreservesPlanRetrievalMetadataAndProvenance() async throws {
    let input = ReviewWorkflowInput(
      transcript: """
        I need to follow up with Jamie tomorrow about the permissions copy.
        We decided to keep local-first extraction as the default.
        """,
      annotations: ["User marked this as a launch follow-up."]
    )
    let generatedDraft = ReviewDraft(
      summary: "Jamie follow-up and local-first extraction decision.",
      tasks: ["Send Jamie the permissions copy"],
      decisions: ["Keep local-first extraction as the default"],
      dates: ["tomorrow"],
      relatedSnippetIDs: ["permissions#0"],
      needsReview: false
    )
    let workflow = makeReviewWorkflow(generatedDraft: generatedDraft)

    let result = try await workflow.run(
      input,
      options: LLMWorkflowOptions(captureIntermediateOutputs: true),
      context: workflowContext(for: input)
    )

    #expect(result.output == generatedDraft)
    #expect(result.fallbackReason == nil)
    #expect(result.validationIssues.isEmpty)
    #expect(result.providerMetadata.map(\.providerKind).contains(.testDouble))
    #expect(result.budgetReport.estimatedInputTokens == 128)
    #expect(result.budgetReport.estimatedOutputTokens == 44)
    #expect(result.retrievalResults.first?.packedSnippets.map(\.id) == ["permissions#0"])
    #expect(result.sourceReferences.map(\.id) == ["permissions"])
    #expect(result.evidence.map(\.id).contains("task-0"))
    #expect(result.evidence.map(\.id).contains("retrieved-0"))
    #expect(result.intermediateOutputs.map(\.stepID).contains("detect-hints"))
    #expect(result.intermediateOutputs.map(\.stepID).contains("plan-context"))
    #expect(result.contextPlan?.items.map(\.surface).contains(.retrievedContext) == true)
    #expect(result.contextPlan?.items.first(where: { $0.surface == .prompt })?.text.contains("User marked") == true)
    #expect(result.events.map(\.kind).contains(.retrievalCompleted))
    #expect(result.events.map(\.kind).contains(.validationCompleted))
  }

  @Test
  func validationFailureFallsBackToDeterministicOutput() async throws {
    let input = ReviewWorkflowInput(
      transcript: "I need to follow up with Jamie tomorrow about the permissions copy.",
      annotations: []
    )
    let generatedDraft = ReviewDraft(
      summary: "Travel booking.",
      tasks: ["Book flights to Lisbon"],
      decisions: [],
      dates: [],
      relatedSnippetIDs: [],
      needsReview: false
    )
    let fallbackDraft = ReviewDraft(
      summary: "Deterministic fallback from transcript hints.",
      tasks: ["follow up with Jamie tomorrow"],
      decisions: [],
      dates: ["tomorrow"],
      relatedSnippetIDs: [],
      needsReview: true
    )
    let workflow = makeReviewWorkflow(
      generatedDraft: generatedDraft,
      fallbackDraft: fallbackDraft,
      evidence: { _, _ in
        [
          EvidenceSpan(
            id: "task-0",
            text: "Book flights to Lisbon",
            sourceID: "transcript"
          )
        ]
      }
    )

    let result = try await workflow.run(input, context: workflowContext(for: input))

    #expect(result.output == fallbackDraft)
    #expect(result.fallbackReason == .validationFailed)
    #expect(result.validationIssues.map(\.id) == ["ungrounded-evidence-task-0"])
    #expect(result.providerMetadata.map(\.providerKind).contains(.testDouble))
    #expect(result.events.map(\.kind).contains(.fallbackApplied))
  }

  @Test
  func retrievalContextPackingIsIncludedInContextPlan() async throws {
    let input = ReviewWorkflowInput(
      transcript: "Please follow up with Jamie about permissions tomorrow.",
      annotations: []
    )
    let workflow = makeReviewWorkflow(
      generatedDraft: ReviewDraft(
        summary: "Jamie follow-up.",
        tasks: ["Follow up with Jamie"],
        decisions: [],
        dates: ["tomorrow"],
        relatedSnippetIDs: ["permissions#0"],
        needsReview: false
      )
    )

    let result = try await workflow.run(input, context: workflowContext(for: input))
    let retrievedContext = result.contextPlan?.items.first {
      $0.surface == .retrievedContext
    }

    #expect(retrievedContext?.text.contains("Permissions note") == true)
    #expect(retrievedContext?.text.contains("Jamie owns the permissions copy") == true)
    #expect(result.budgetReport.contextReports.map(\.stepID).contains("retrieve-notes"))
    #expect(result.budgetReport.contextReports.map(\.stepID).contains("plan-context"))
  }

  @Test
  func workflowPropagatesCancellation() async {
    let slowStep: LLMStep<Int, Int> = .deterministicTransform(id: "slow") { input, _ in
      try await Task.sleep(for: .seconds(5))
      return input
    }
    let workflow = LLMWorkflow(slowStep)
    let task = Task {
      try await workflow.run(1)
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}

private func makeReviewWorkflow(
  generatedDraft: ReviewDraft,
  fallbackDraft: ReviewDraft = ReviewDraft(
    summary: "Deterministic fallback from transcript hints.",
    tasks: ["follow up with Jamie tomorrow"],
    decisions: [],
    dates: ["tomorrow"],
    relatedSnippetIDs: [],
    needsReview: true
  ),
  evidence: @escaping @Sendable (
    ReviewDraft,
    LLMWorkflowContext
  ) -> [EvidenceSpan] = defaultReviewEvidence
) -> LLMWorkflow<ReviewWorkflowInput, ReviewDraft> {
  let detectHints: LLMStep<ReviewWorkflowInput, ReviewWorkflowState> =
    .deterministicTransform(
      id: "detect-hints",
      captureIntermediateOutput: { state in
        LLMWorkflowIntermediateOutput(
          id: "detect-hints-output",
          stepID: "detect-hints",
          label: "Deterministic hints",
          payload: .json([
            "dateHintCount": .number(Double(state.hints.dateHints.count)),
            "decisionHintCount": .number(Double(state.hints.decisionHints.count)),
            "taskHintCount": .number(Double(state.hints.taskHints.count)),
          ])
        )
      }
    ) { input, _ in
      ReviewWorkflowState(
        input: input,
        hints: TranscriptHints(transcript: input.transcript)
      )
    }

  let retrievalPipeline = LocalRAGPipeline(
    retriever: KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "permissions",
          text: "Jamie owns the permissions copy. Local extraction should cite this related note.",
          displayName: "Permissions note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 48
    ),
    packer: ContextPacker(
      budget: TokenBudget(
        contextLimit: 256,
        reservedResponseTokens: 64,
        safetyMarginTokens: 16
      ),
      strategy: .sourceDiverse
    )
  )
  let retrieveNotes: LLMStep<ReviewWorkflowState, ReviewWorkflowState> =
    .localRetrieval(id: "retrieve-notes", pipeline: retrievalPipeline) { state, _ in
      LocalRetrievalQuery(
        text: ([state.input.transcript] + state.hints.taskHints).joined(separator: " "),
        maxResults: 3
      )
    }

  let planContext: LLMStep<ReviewWorkflowState, CompiledPrompt> =
    .contextPlanning(id: "plan-context") { state, context in
      let contract = PromptContract(
        id: "review-draft",
        version: "workflow-v1",
        instructions: "Extract only grounded summary, tasks, dates, and decisions.",
        responseSchemaDescription: "Return compact structured review data with evidence."
      )
      let examples = ExampleSelector(limit: 1, preferredTags: ["task"]).select(
        from: [
          PromptExample(
            id: "task-example",
            input: "I need to email Jamie tomorrow.",
            output: #"{"tasks":["email Jamie"],"dates":["tomorrow"]}"#,
            tags: ["task"]
          ),
          PromptExample(
            id: "decision-example",
            input: "We decided to ship local first.",
            output: #"{"decisions":["ship local first"]}"#,
            tags: ["decision"]
          ),
        ]
      )
      let retrievedContext = context.retrievalResults.last?.contextBlock ?? ""
      let userPrompt = """
        Transcript:
        \(state.input.transcript)

        Annotations:
        \(state.input.annotations.joined(separator: "\n"))

        Deterministic hints:
        tasks=\(state.hints.taskHints)
        decisions=\(state.hints.decisionHints)
        dates=\(state.hints.dateHints)
        """
      let plan = LLMContextPlan(
        items: [
          LLMContextItem(
            id: "instructions",
            surface: .instructions,
            text: contract.instructions,
            trust: .trustedSystem
          ),
          LLMContextItem(
            id: "prompt",
            surface: .prompt,
            text: userPrompt,
            trust: .userProvided
          ),
          LLMContextItem(
            id: "schema",
            surface: .generatedSchema,
            text: contract.responseSchemaDescription,
            trust: .trustedApp
          ),
          LLMContextItem(
            id: "deterministic-hints",
            surface: .prompt,
            text: state.hints.promptFragment,
            trust: .trustedApp
          ),
          LLMContextItem(
            id: "retrieved-notes",
            surface: .retrievedContext,
            text: retrievedContext,
            trust: .trustedApp,
            estimatedTokens: context.counter.count(retrievedContext)
          ),
        ],
        sessionPolicy: .statelessPerRequest,
        toolExecutionPolicy: .appPrefetches
      )

      return CompiledPrompt(
        contract: contract,
        examples: examples,
        contextPlan: plan,
        metadata: reviewMetadata,
        userPrompt: userPrompt
      )
    }

  let generateDraft:
    LLMStep<CompiledPrompt, StructuredGenerationCandidate<ReviewDraft>> =
      .modelGeneration(
        id: "generate-draft",
        generate: { prompt in
          GenerationCandidate(
            output: generatedDraft,
            metadata: prompt.metadata,
            tokenUsage: LLMTokenUsage(
              estimatedInputTokens: 128,
              estimatedOutputTokens: 44,
              measuredInputTokens: 121,
              measuredOutputTokens: 38
            )
          )
        },
        evidence: evidence
      )

  let validateDraft:
    LLMStep<
      StructuredGenerationCandidate<ReviewDraft>,
      StructuredGenerationPipelineResult<ReviewDraft>
    > = .structuredValidation(
      id: "validate-grounding",
      validator: .groundedEvidence()
    )

  let fallback:
    LLMStep<StructuredGenerationPipelineResult<ReviewDraft>, ReviewDraft> =
      .repairOrFallback(
        id: "repair-or-fallback",
        repairPolicy: .fallbackOnValidationFailure(notes: "Use deterministic hints."),
        fallbackPolicy: .fixed(fallbackDraft)
      )

  return LLMWorkflow(detectHints)
    .then(retrieveNotes)
    .then(planContext)
    .then(generateDraft)
    .then(validateDraft)
    .then(fallback)
}

private func workflowContext(for input: ReviewWorkflowInput) -> LLMWorkflowContext {
  LLMWorkflowContext(
    budget: TokenBudget(
      contextLimit: 256,
      reservedResponseTokens: 64,
      safetyMarginTokens: 16
    ),
    sourceContext: StructuredGenerationSourceContext(
      sources: [
        EvidenceSource(
          id: "transcript",
          text: input.transcript,
          displayName: "Transcript",
          kind: "transcript"
        )
      ]
    )
  )
}

private let reviewMetadata = LLMProviderMetadata(
  modelIdentifier: "fake-structured-generator",
  privacyMode: .localOnly,
  promptVersion: "workflow-v1",
  providerDisplayName: "Fake Structured Generator",
  providerKind: .testDouble
)

private func defaultReviewEvidence(
  _ draft: ReviewDraft,
  _ context: LLMWorkflowContext
) -> [EvidenceSpan] {
  [
    EvidenceSpan(
      id: "task-0",
      text: "follow up with Jamie tomorrow",
      sourceID: "transcript"
    ),
    EvidenceSpan(
      id: "decision-0",
      text: "decided to keep local-first extraction",
      sourceID: "transcript"
    ),
    EvidenceSpan(
      id: "retrieved-0",
      text: "Jamie owns the permissions copy",
      sourceID: context.retrievalResults.first?.packedSnippets.first?.id
    ),
  ]
}

private struct ReviewWorkflowInput: Equatable, Sendable {
  var transcript: String
  var annotations: [String]
}

private struct ReviewWorkflowState: Equatable, Sendable {
  var input: ReviewWorkflowInput
  var hints: TranscriptHints
}

private struct TranscriptHints: Equatable, Sendable {
  var dateHints: [String]
  var decisionHints: [String]
  var taskHints: [String]

  init(transcript: String) {
    let lowercased = transcript.lowercased()
    self.dateHints = lowercased.contains("tomorrow") ? ["tomorrow"] : []
    self.decisionHints = lowercased.contains("decided")
      ? ["decided to keep local-first extraction"]
      : []
    self.taskHints = lowercased.contains("follow up")
      ? ["follow up with Jamie tomorrow"]
      : []
  }

  var promptFragment: String {
    """
    Task hints: \(taskHints.joined(separator: ", "))
    Decision hints: \(decisionHints.joined(separator: ", "))
    Date hints: \(dateHints.joined(separator: ", "))
    """
  }
}

private struct ReviewDraft: Equatable, Sendable {
  var summary: String
  var tasks: [String]
  var decisions: [String]
  var dates: [String]
  var relatedSnippetIDs: [String]
  var needsReview: Bool
}
