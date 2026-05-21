import Foundation
import SwiftLLM
import SwiftLLMEvaluation
import SwiftLLMFoundationModels
import Testing

@Suite("SwiftLLM")
struct SwiftLLMTests {
  struct SampleExtraction: Equatable, Sendable {
    var summary: String
    var tasks: [String]
  }

  @Test
  func tokenBudgetReservesResponseAndSafetyMargin() {
    let budget = TokenBudget(
      contextLimit: 4_096,
      reservedResponseTokens: 700,
      safetyMarginTokens: 300
    )

    #expect(budget.availableInputTokens == 3_096)
  }

  @Test
  func textChunkerSplitsLargeInput() {
    let chunker = TextChunker(
      maxTokensPerChunk: 16,
      overlapTokens: 4
    )
    let text = Array(repeating: "Follow up with Jamie tomorrow after the launch review.", count: 8)
      .joined(separator: " ")

    let chunks = chunker.chunks(for: text)

    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.tokenCount <= 16 })
    #expect(chunks.allSatisfy { !$0.characterRange.isEmpty })
  }

  @Test
  func contextPackerSelectsHighestScoringSnippetsWithinBudget() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 20,
        reservedResponseTokens: 4,
        safetyMarginTokens: 1
      )
    )
    let snippets = [
      RetrievedSnippet(id: "low", sourceID: "a", text: "Low", tokenCount: 4, score: 0.1),
      RetrievedSnippet(id: "high", sourceID: "b", text: "High", tokenCount: 10, score: 0.9),
      RetrievedSnippet(id: "too-large", sourceID: "c", text: "Large", tokenCount: 20, score: 1.0),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["high", "low"])
  }

  @Test
  func contextPackerCanPreferScoreDensity() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 12,
        reservedResponseTokens: 1,
        safetyMarginTokens: 1
      ),
      strategy: .scoreDensity
    )
    let snippets = [
      RetrievedSnippet(id: "big", sourceID: "a", text: "Big", tokenCount: 10, score: 0.9),
      RetrievedSnippet(id: "dense", sourceID: "b", text: "Dense", tokenCount: 2, score: 0.4),
      RetrievedSnippet(id: "small", sourceID: "c", text: "Small", tokenCount: 2, score: 0.3),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["dense", "small"])
  }

  @Test
  func contextPackerCanDiversifySources() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 20,
        reservedResponseTokens: 1,
        safetyMarginTokens: 1
      ),
      strategy: .sourceDiverse
    )
    let snippets = [
      RetrievedSnippet(id: "a1", sourceID: "a", text: "A1", tokenCount: 3, score: 0.9),
      RetrievedSnippet(id: "a2", sourceID: "a", text: "A2", tokenCount: 3, score: 0.8),
      RetrievedSnippet(id: "b1", sourceID: "b", text: "B1", tokenCount: 3, score: 0.7),
      RetrievedSnippet(id: "c1", sourceID: "c", text: "C1", tokenCount: 3, score: 0.6),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["a1", "b1", "c1", "a2"])
  }

  @Test
  func exampleSelectorPrefersMatchingTags() {
    let examples = [
      PromptExample(id: "general", input: "A", output: "B", tags: ["general"]),
      PromptExample(id: "meeting", input: "C", output: "D", tags: ["meeting"]),
    ]

    let selected = ExampleSelector(limit: 1, preferredTags: ["meeting"])
      .select(from: examples)

    #expect(selected.map(\.id) == ["meeting"])
  }

  @Test
  func groundingValidatorRejectsUnsupportedOutput() {
    let validator = GroundingValidator()

    #expect(
      validator.isGrounded(
        "Send Jamie the permissions copy",
        in: "I need to send Jamie the permissions copy tomorrow."
      )
    )
    #expect(
      !validator.isGrounded(
        "Book flights to Lisbon",
        in: "I need to send Jamie the permissions copy tomorrow."
      )
    )
  }

  @Test
  func promptEvaluatorChecksRequiredAndForbiddenText() {
    let evaluator = PromptEvaluator()
    let result = evaluator.evaluate(
      PromptEvaluationCase(
        id: "summary",
        input: "Summarize",
        requiredSubstrings: ["privacy"],
        forbiddenSubstrings: ["uploaded"]
      ),
      output: "The workflow keeps privacy local."
    )

    #expect(result.passed)
  }

  @Test
  func promptEvaluatorRunsTextAssertions() {
    let evaluator = PromptEvaluator()
    let result = evaluator.evaluate(
      PromptEvaluationCase(
        id: "citations",
        input: "Answer with citations.",
        assertions: [
          .contains("[1]"),
          .minimumOccurrences("local", 2),
          .maximumLength(80),
        ]
      ),
      output: "Local retrieval keeps local citations visible. [1]"
    )

    #expect(result.passed)
  }

  @Test
  func structuredOutputEvaluatorReportsTypedIssues() {
    let evaluator = StructuredOutputEvaluator<SampleExtraction>(
      assertions: [
        .nonEmptyString(\.summary, id: "summary-required", path: "summary"),
        .maximumCount(\.tasks, maximum: 2, id: "task-limit", path: "tasks"),
      ]
    )

    let result = evaluator.evaluate(
      caseID: "sample",
      output: SampleExtraction(
        summary: "",
        tasks: ["One", "Two", "Three"]
      )
    )

    #expect(!result.passed)
    #expect(result.issues.map(\.id) == ["summary-required", "task-limit"])
  }

  @Test
  func promptEvaluationReportRedactsOutputsByDefault() throws {
    let prompt = PromptContract(
      id: "review",
      version: "v2",
      instructions: "Extract."
    )
    let report = PromptVersionEvaluationReport(
      prompt: prompt,
      results: [
        PromptEvaluationResult(
          caseID: "case-1",
          output: "Raw local output",
          failures: []
        )
      ],
      metrics: EvaluationRunMetrics(
        estimatedInputTokens: 20,
        estimatedOutputTokens: 8,
        retrievalSnippetCount: 2
      ),
      createdAt: Date(timeIntervalSince1970: 0)
    )

    let json = String(decoding: try report.jsonData(), as: UTF8.self)

    #expect(report.passed)
    #expect(!report.storesRawOutputs)
    #expect(report.caseResults.first?.output == nil)
    #expect(json.contains("\"promptVersion\" : \"v2\""))
    #expect(!json.contains("Raw local output"))
  }

  @Test
  func localDebugBundleAggregatesPromptAndFallbackMatrices() throws {
    let report = PromptVersionEvaluationReport(
      id: "report",
      promptID: "review",
      promptVersion: "v1",
      caseResults: [
        PromptEvaluationResultRecord(
          caseID: "case-1",
          passed: true,
          failures: []
        )
      ],
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let fallbackMatrix = ModelFallbackMatrix(
      entries: [
        ModelFallbackMatrixEntry(
          providerKind: "appleFoundationModels",
          availability: "available",
          passedCaseCount: 1,
          failedCaseCount: 0,
          modelIdentifier: "system"
        )
      ]
    )
    let bundle = LocalDebugBundle(
      id: "bundle",
      promptReports: [report],
      modelFallbackMatrix: fallbackMatrix,
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let json = String(decoding: try bundle.jsonData(), as: UTF8.self)

    #expect(bundle.passed)
    #expect(bundle.contentPolicy == .redacted)
    #expect(json.contains("\"contentPolicy\" : \"redacted\""))
    #expect(json.contains("\"providerKind\" : \"appleFoundationModels\""))
  }

  @Test
  func foundationModelAvailabilityMapsUnavailableStateToFallback() {
    let availability = FoundationModelAvailability.modelNotReady

    #expect(!availability.isAvailable)
    #expect(availability.fallbackReason == .unavailable)
    #expect(availability.diagnosticMessage == "The local language model is not ready.")
  }

  @Test
  func foundationModelFailureMapsContextErrorToFallback() {
    let failure = FoundationModelFailure(
      reason: .contextExceeded,
      debugDescription: "Prompt used too many tokens."
    )

    #expect(failure.fallbackReason == .contextExceeded)
    #expect(failure.errorDescription == "The request exceeded the Foundation Models context window.")
  }

  @Test
  func foundationModelFakeClientCanExerciseGenerationWithoutFramework() async throws {
    let metadata = FoundationModelDefaults.metadata(promptVersion: "test-v1")
    let contract = PromptContract(
      id: "summary",
      version: "v1",
      instructions: "Summarize in one sentence."
    )
    let prompt = CompiledPrompt(
      contract: contract,
      metadata: metadata,
      userPrompt: "Summarize this local transcript."
    )
    let startedAt = Date(timeIntervalSince1970: 10)
    let completedAt = Date(timeIntervalSince1970: 11)
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        FoundationModelGenerationResponse(
          content: "This is a local summary.",
          metadata: request.prompt.metadata,
          tokenUsage: LLMTokenUsage(
            estimatedInputTokens: 8,
            estimatedOutputTokens: 6
          ),
          startedAt: startedAt,
          completedAt: completedAt
        )
      }
    )

    let response = try await client.respond(
      FoundationModelGenerationRequest(
        prompt: prompt,
        options: FoundationModelGenerationOptions(maximumResponseTokens: 64)
      )
    )

    #expect(response.content == "This is a local summary.")
    #expect(response.metadata.promptVersion == "test-v1")
    #expect(response.tokenUsage.estimatedInputTokens == 8)
    #expect(response.candidate.output == "This is a local summary.")
  }

  @Test
  func unavailableFoundationModelClientFallsBackToHeuristicTokenCounting() async throws {
    let count = try await FoundationModelClient.unavailable.countTokens(
      FoundationModelTokenCountRequest(text: "A short local prompt")
    )

    #expect(count == TokenCounter.latinHeuristic.count("A short local prompt"))
    #expect(FoundationModelClient.unavailable.availability() == .unavailableInBuild)
  }

  @Test
  func structuredSchemaProducesPromptDescription() {
    let schema = StructuredGenerationSchema(
      id: "sample",
      name: "Sample extraction",
      description: "Return a short summary and tasks.",
      fields: [
        StructuredGenerationField(
          name: "summary",
          typeDescription: "String",
          guide: "One sentence."
        ),
        StructuredGenerationField(
          name: "tasks",
          typeDescription: "[String]",
          isRequired: false,
          maximumCount: 3
        ),
      ],
      maximumResponseTokens: 120
    )

    #expect(schema.promptDescription.contains("summary"))
    #expect(schema.promptDescription.contains("maximum count 3"))
    #expect(schema.promptDescription.contains("Maximum response tokens: 120"))
  }

  @Test
  func structuredValidatorCombinesCountAndGroundedEvidenceRules() {
    let metadata = FoundationModelDefaults.metadata(promptVersion: "test")
    let candidate = StructuredGenerationCandidate(
      output: SampleExtraction(
        summary: "Review local extraction",
        tasks: ["One", "Two", "Three"]
      ),
      metadata: metadata,
      evidence: [
        EvidenceSpan(
          id: "summary",
          text: "Review local extraction",
          sourceID: "transcript"
        )
      ]
    )
    let validator = StructuredGenerationValidator<SampleExtraction>.all([
      .maximumCount(\.tasks, maximum: 2, path: "tasks"),
      .groundedEvidence(),
    ])
    let result = validator(
      candidate,
      in: StructuredGenerationSourceContext(
        sources: [
          EvidenceSource(
            id: "transcript",
            text: "We need to review local extraction tomorrow."
          )
        ]
      )
    )

    #expect(!result.isAccepted)
    #expect(result.issues.map(\.id).contains("maximum-count-tasks"))
  }

  @Test
  func structuredPipelineAcceptsValidCandidate() async {
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "sample", version: "v1", instructions: "Extract."),
      metadata: FoundationModelDefaults.metadata(promptVersion: "test"),
      userPrompt: "Need to review local extraction."
    )
    let pipeline = StructuredGenerationPipeline<SampleExtraction>(
      generate: { prompt in
        GenerationCandidate(
          output: SampleExtraction(
            summary: "Review local extraction",
            tasks: ["Review local extraction"]
          ),
          metadata: prompt.metadata
        )
      },
      validator: .all([
        .nonEmptyString(\.summary, path: "summary"),
        .maximumCount(\.tasks, maximum: 2, path: "tasks"),
        .groundedEvidence(),
      ])
    )

    let result = await pipeline.run(
      prompt: prompt,
      context: StructuredGenerationSourceContext(
        sourceText: "Need to review local extraction."
      ),
      evidence: { output in
        [EvidenceSpan(id: "summary", text: output.summary, sourceID: "source")]
      }
    )

    #expect(result.status == .accepted)
    #expect(result.output?.summary == "Review local extraction")
    #expect(result.validation.isAccepted)
  }

  @Test
  func structuredPipelineFallsBackOnValidationFailure() async {
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "sample", version: "v1", instructions: "Extract."),
      metadata: FoundationModelDefaults.metadata(promptVersion: "test"),
      userPrompt: "Need to review local extraction."
    )
    let fallback = SampleExtraction(summary: "Fallback summary", tasks: [])
    let pipeline = StructuredGenerationPipeline<SampleExtraction>(
      generate: { prompt in
        GenerationCandidate(
          output: SampleExtraction(
            summary: "",
            tasks: ["One", "Two", "Three"]
          ),
          metadata: prompt.metadata
        )
      },
      validator: .all([
        .nonEmptyString(\.summary, path: "summary"),
        .maximumCount(\.tasks, maximum: 2, path: "tasks"),
      ]),
      repairPolicy: .fallbackOnValidationFailure(notes: "Use deterministic fallback."),
      fallbackPolicy: .fixed(fallback)
    )

    let result = await pipeline.run(prompt: prompt)

    #expect(result.status == .fellBack)
    #expect(result.output == fallback)
    #expect(result.fallbackDecision?.reason == .validationFailed)
    #expect(result.repairPlan.action == .fallback(.validationFailed))
  }

  @Test
  func boundaryAwareChunkerPreservesSentenceBoundaries() {
    let text = "First sentence is short. Second sentence has more content. Third sentence closes."
    let chunker = BoundaryAwareTextChunker(
      boundary: .sentence,
      maxTokensPerChunk: 10,
      overlapUnitCount: 1
    )

    let chunks = chunker.chunks(for: text)

    #expect(chunks.count > 1)
    #expect(chunks.first?.text.hasSuffix(".") == true)
    #expect(chunks.allSatisfy { !$0.characterRange.isEmpty })
  }

  @Test
  func transcriptChunkerPreservesSegmentIDsAndTimes() {
    let segments = [
      TranscriptSegment(id: "1", text: "Need to follow up with Jamie tomorrow.", startTime: 0, endTime: 4),
      TranscriptSegment(id: "2", text: "We decided to keep the local version first.", startTime: 4, endTime: 9),
      TranscriptSegment(id: "3", text: "Compare prompt versions before publishing.", startTime: 9, endTime: 13),
    ]
    let chunker = TranscriptChunker(
      maxTokensPerChunk: 24,
      overlapSegmentCount: 1,
      sourceID: "recording-1"
    )

    let chunks = chunker.chunks(for: segments)

    #expect(chunks.count > 1)
    #expect(chunks[0].segmentIDs == ["1", "2"])
    #expect(chunks[1].segmentIDs.first == "2")
    #expect(chunks[0].startTime == 0)
    #expect(chunks[0].endTime == 9)
    #expect(chunks[0].evidenceSource.kind == "transcriptChunk")
  }

  @Test
  func mergePolicyDeduplicatesByNormalizedText() {
    let merged = MergePolicy<String>.normalizedText.merged([
      "Send Jamie the permissions copy",
      "send jamie the permissions copy.",
      "Review prompt versions",
    ])

    #expect(merged == [
      "Send Jamie the permissions copy",
      "Review prompt versions",
    ])
  }

  @Test
  func mapReducePipelineProcessesChunksInOrder() async throws {
    let chunks = [
      TranscriptChunk(
        id: 0,
        sourceID: "recording",
        text: "Need to follow up.",
        segmentIDs: ["1"],
        tokenCount: 5
      ),
      TranscriptChunk(
        id: 1,
        sourceID: "recording",
        text: "Review prompt versions.",
        segmentIDs: ["2"],
        tokenCount: 6
      ),
    ]
    let pipeline = MapReducePipeline<TranscriptChunk, String, String>(
      map: { chunk in
        ChunkProcessingResult(
          chunk: chunk,
          output: chunk.text.uppercased(),
          evidence: [
            EvidenceSpan(
              id: "chunk-\(chunk.id)",
              text: chunk.text,
              sourceID: chunk.evidenceSource.id
            )
          ]
        )
      },
      reduce: { partials in
        partials.map(\.output).joined(separator: " ")
      }
    )

    let result = try await pipeline.run(chunks: chunks)

    #expect(result.partials.count == 2)
    #expect(result.output == "NEED TO FOLLOW UP. REVIEW PROMPT VERSIONS.")
  }

  @Test
  func keywordLocalRetrieverRanksMatchingLocalDocuments() async throws {
    let meetingText = "We need local extraction with grounded citations for Chime In."
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "meeting",
          text: meetingText,
          displayName: "Launch meeting",
          kind: "transcript"
        ),
        RetrievableDocument(
          id: "unrelated",
          text: "The design review covered colors and spacing.",
          displayName: "Design review",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 40
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(text: "local extraction citations", maxResults: 4)
    )

    #expect(result.snippets.map(\.sourceID) == ["meeting"])
    #expect(result.snippets.first?.sourceDisplayName == "Launch meeting")
    #expect(result.snippets.first?.sourceKind == "transcript")
    #expect(result.snippets.first?.characterRange == 0..<meetingText.count)
    #expect(result.sources.map(\.id) == ["meeting"])
  }

  @Test
  func localRAGPipelinePacksContextAndBuildsCitations() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "one",
          text: "Local retrieval keeps private notes on device.",
          displayName: "Private note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "two",
          text: "Prompt contracts should include compact citation context.",
          displayName: "Prompt plan",
          kind: "doc"
        ),
      ],
      maxTokensPerSnippet: 32
    )
    let pipeline = LocalRAGPipeline(
      retriever: retriever,
      packer: ContextPacker(
        budget: TokenBudget(
          contextLimit: 64,
          reservedResponseTokens: 8,
          safetyMarginTokens: 4
        ),
        strategy: .sourceDiverse
      )
    )

    let result = try await pipeline.run(
      query: LocalRetrievalQuery(text: "local citation context", maxResults: 4)
    )

    #expect(result.packedSnippets.count == 2)
    #expect(result.citations.map(\.marker) == ["1", "2"])
    #expect(result.contextBlock.contains("Private note (note)"))
    #expect(result.contextBlock.contains("Prompt plan (doc)"))
    #expect(result.sourceContext.sources.map(\.id) == result.packedSnippets.map(\.id))
  }
}
