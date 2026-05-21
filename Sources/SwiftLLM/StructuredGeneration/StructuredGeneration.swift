import Foundation

public struct StructuredGenerationSchema: Equatable, Identifiable, Sendable {
  public var description: String
  public var fields: [StructuredGenerationField]
  public var id: String
  public var maximumItemCount: Int?
  public var maximumResponseTokens: Int?
  public var name: String

  public init(
    id: String,
    name: String,
    description: String,
    fields: [StructuredGenerationField] = [],
    maximumItemCount: Int? = nil,
    maximumResponseTokens: Int? = nil
  ) {
    self.description = description
    self.fields = fields
    self.id = id
    self.maximumItemCount = maximumItemCount
    self.maximumResponseTokens = maximumResponseTokens
    self.name = name
  }
}

public struct StructuredGenerationField: Equatable, Identifiable, Sendable {
  public var guide: String?
  public var id: String { name }
  public var isRequired: Bool
  public var maximumCount: Int?
  public var name: String
  public var typeDescription: String

  public init(
    name: String,
    typeDescription: String,
    isRequired: Bool = true,
    guide: String? = nil,
    maximumCount: Int? = nil
  ) {
    self.guide = guide
    self.isRequired = isRequired
    self.maximumCount = maximumCount
    self.name = name
    self.typeDescription = typeDescription
  }
}

public struct StructuredGenerationContract: Equatable, Identifiable, Sendable {
  public var examples: [PromptExample]
  public var id: String { prompt.id }
  public var prompt: PromptContract
  public var schema: StructuredGenerationSchema

  public init(
    prompt: PromptContract,
    schema: StructuredGenerationSchema,
    examples: [PromptExample] = []
  ) {
    self.examples = examples
    self.prompt = prompt
    self.schema = schema
  }

  public func compiledPrompt(
    metadata: LLMProviderMetadata,
    userPrompt: String
  ) -> CompiledPrompt {
    CompiledPrompt(
      contract: PromptContract(
        id: prompt.id,
        version: prompt.version,
        instructions: prompt.instructions,
        responseSchemaDescription: schema.promptDescription
      ),
      examples: examples,
      metadata: metadata,
      userPrompt: userPrompt
    )
  }
}

extension StructuredGenerationSchema {
  public var promptDescription: String {
    let fieldDescriptions = fields.map { field in
      var pieces = [
        "- \(field.name): \(field.typeDescription)",
        field.isRequired ? "required" : "optional",
      ]
      if let maximumCount = field.maximumCount {
        pieces.append("maximum count \(maximumCount)")
      }
      if let guide = field.guide, !guide.isEmpty {
        pieces.append(guide)
      }
      return pieces.joined(separator: "; ")
    }

    let limitDescription: String
    switch (maximumItemCount, maximumResponseTokens) {
    case let (.some(items), .some(tokens)):
      limitDescription = "\nMaximum items: \(items). Maximum response tokens: \(tokens)."
    case let (.some(items), .none):
      limitDescription = "\nMaximum items: \(items)."
    case let (.none, .some(tokens)):
      limitDescription = "\nMaximum response tokens: \(tokens)."
    case (.none, .none):
      limitDescription = ""
    }

    guard !fieldDescriptions.isEmpty else {
      return "\(description)\(limitDescription)"
    }

    return """
    \(description)
    Fields:
    \(fieldDescriptions.joined(separator: "\n"))
    \(limitDescription)
    """
  }
}

public struct EvidenceSource: Equatable, Identifiable, Sendable {
  public var displayName: String?
  public var id: String
  public var kind: String?
  public var text: String

  public init(
    id: String,
    text: String,
    displayName: String? = nil,
    kind: String? = nil
  ) {
    self.displayName = displayName
    self.id = id
    self.kind = kind
    self.text = text
  }
}

public struct EvidenceSpan: Equatable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var confidence: Double?
  public var id: String
  public var sourceID: EvidenceSource.ID?
  public var text: String

  public init(
    id: String,
    text: String,
    sourceID: EvidenceSource.ID? = nil,
    characterRange: Range<Int>? = nil,
    confidence: Double? = nil
  ) {
    self.characterRange = characterRange
    self.confidence = confidence
    self.id = id
    self.sourceID = sourceID
    self.text = text
  }
}

public struct StructuredGenerationSourceContext: Equatable, Sendable {
  public var sources: [EvidenceSource]

  public init(sources: [EvidenceSource] = []) {
    self.sources = sources
  }

  public init(sourceText: String, sourceID: String = "source") {
    self.sources = [
      EvidenceSource(id: sourceID, text: sourceText)
    ]
  }

  public func sourceText(for sourceID: EvidenceSource.ID?) -> String {
    guard let sourceID,
      let source = sources.first(where: { $0.id == sourceID })
    else {
      return sources.map(\.text).joined(separator: "\n\n")
    }

    return source.text
  }
}

public struct StructuredGenerationCandidate<Output: Sendable>: Sendable {
  public var evidence: [EvidenceSpan]
  public var metadata: LLMProviderMetadata
  public var output: Output
  public var rawOutputDescription: String?
  public var tokenUsage: LLMTokenUsage?

  public init(
    output: Output,
    metadata: LLMProviderMetadata,
    evidence: [EvidenceSpan] = [],
    tokenUsage: LLMTokenUsage? = nil,
    rawOutputDescription: String? = nil
  ) {
    self.evidence = evidence
    self.metadata = metadata
    self.output = output
    self.rawOutputDescription = rawOutputDescription
    self.tokenUsage = tokenUsage
  }

  public init(
    generationCandidate: GenerationCandidate<Output>,
    evidence: [EvidenceSpan] = [],
    rawOutputDescription: String? = nil
  ) {
    self.init(
      output: generationCandidate.output,
      metadata: generationCandidate.metadata,
      evidence: evidence,
      tokenUsage: generationCandidate.tokenUsage,
      rawOutputDescription: rawOutputDescription
    )
  }

  public var generationCandidate: GenerationCandidate<Output> {
    GenerationCandidate(
      output: output,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

extension StructuredGenerationCandidate: Equatable where Output: Equatable {}

public enum ValidationSeverity: String, Equatable, Sendable {
  case warning
  case error
}

public struct ValidationIssue: Equatable, Identifiable, Sendable {
  public var evidenceID: EvidenceSpan.ID?
  public var id: String
  public var message: String
  public var path: String?
  public var severity: ValidationSeverity

  public init(
    id: String,
    message: String,
    severity: ValidationSeverity = .error,
    path: String? = nil,
    evidenceID: EvidenceSpan.ID? = nil
  ) {
    self.evidenceID = evidenceID
    self.id = id
    self.message = message
    self.path = path
    self.severity = severity
  }
}

public struct StructuredGenerationValidationResult: Equatable, Sendable {
  public var issues: [ValidationIssue]

  public init(issues: [ValidationIssue] = []) {
    self.issues = issues
  }

  public var isAccepted: Bool {
    !issues.contains { $0.severity == .error }
  }

  public static let accepted = Self()

  public static func + (
    lhs: Self,
    rhs: Self
  ) -> Self {
    Self(issues: lhs.issues + rhs.issues)
  }
}

public struct StructuredGenerationValidator<Output: Sendable>: Sendable {
  public var validate:
    @Sendable (
      StructuredGenerationCandidate<Output>,
      StructuredGenerationSourceContext
    ) -> StructuredGenerationValidationResult

  public init(
    validate: @escaping @Sendable (
      StructuredGenerationCandidate<Output>,
      StructuredGenerationSourceContext
    ) -> StructuredGenerationValidationResult
  ) {
    self.validate = validate
  }

  public func callAsFunction(
    _ candidate: StructuredGenerationCandidate<Output>,
    in context: StructuredGenerationSourceContext
  ) -> StructuredGenerationValidationResult {
    validate(candidate, context)
  }

  public func combined(
    with other: Self
  ) -> Self {
    Self { candidate, context in
      self(candidate, in: context) + other(candidate, in: context)
    }
  }

  public static var acceptAll: Self {
    Self { _, _ in .accepted }
  }

  public static func all(_ validators: [Self]) -> Self {
    validators.reduce(.acceptAll) { partial, validator in
      partial.combined(with: validator)
    }
  }

  public static func groundedEvidence(
    validator: GroundingValidator = GroundingValidator()
  ) -> Self {
    Self { candidate, context in
      let issues = candidate.evidence.compactMap { evidence -> ValidationIssue? in
        let sourceText = context.sourceText(for: evidence.sourceID)
        guard validator.isGrounded(evidence.text, in: sourceText)
        else {
          return ValidationIssue(
            id: "ungrounded-evidence-\(evidence.id)",
            message: "Evidence is not grounded in the provided source context.",
            path: "evidence",
            evidenceID: evidence.id
          )
        }
        return nil
      }
      return StructuredGenerationValidationResult(issues: issues)
    }
  }

  public static func maximumCount<Element>(
    _ values: @escaping @Sendable (Output) -> [Element],
    maximum: Int,
    path: String
  ) -> Self {
    Self { candidate, _ in
      let count = values(candidate.output).count
      guard count <= maximum else {
        return StructuredGenerationValidationResult(
          issues: [
            ValidationIssue(
              id: "maximum-count-\(path)",
              message: "Expected at most \(maximum) items but received \(count).",
              path: path
            )
          ]
        )
      }
      return .accepted
    }
  }

  public static func nonEmptyString(
    _ value: @escaping @Sendable (Output) -> String,
    path: String
  ) -> Self {
    Self { candidate, _ in
      guard !value(candidate.output).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return StructuredGenerationValidationResult(
          issues: [
            ValidationIssue(
              id: "empty-string-\(path)",
              message: "Expected non-empty generated text.",
              path: path
            )
          ]
        )
      }
      return .accepted
    }
  }
}

public enum StructuredGenerationRepairAction: Equatable, Sendable {
  case none
  case retryWithShorterContext
  case retryWithFewerExamples
  case retryWithSimplerSchema
  case retryWithMaximumResponseTokens(Int)
  case fallback(FallbackReason)
}

public struct StructuredGenerationRepairPlan: Equatable, Sendable {
  public var action: StructuredGenerationRepairAction
  public var notes: String?
  public var validationIssues: [ValidationIssue]

  public init(
    action: StructuredGenerationRepairAction,
    validationIssues: [ValidationIssue] = [],
    notes: String? = nil
  ) {
    self.action = action
    self.notes = notes
    self.validationIssues = validationIssues
  }

  public static let none = Self(action: .none)
}

public struct StructuredGenerationRepairPolicy<Output: Sendable>: Sendable {
  public var plan:
    @Sendable (
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult,
      FallbackReason?
    ) -> StructuredGenerationRepairPlan

  public init(
    plan: @escaping @Sendable (
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult,
      FallbackReason?
    ) -> StructuredGenerationRepairPlan
  ) {
    self.plan = plan
  }

  public static var none: Self {
    Self { _, _, _ in .none }
  }

  public static func fallbackOnValidationFailure(
    notes: String? = nil
  ) -> Self {
    Self { _, validation, failureReason in
      if let failureReason {
        return StructuredGenerationRepairPlan(
          action: .fallback(failureReason),
          validationIssues: validation.issues,
          notes: notes
        )
      }
      guard !validation.isAccepted else { return .none }
      return StructuredGenerationRepairPlan(
        action: .fallback(.validationFailed),
        validationIssues: validation.issues,
        notes: notes
      )
    }
  }
}

public struct StructuredGenerationFallbackPolicy<Output: Sendable>: Sendable {
  public var resolve:
    @Sendable (
      FallbackReason,
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult
    ) -> Output?

  public init(
    resolve: @escaping @Sendable (
      FallbackReason,
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult
    ) -> Output?
  ) {
    self.resolve = resolve
  }

  public static var none: Self {
    Self { _, _, _ in nil }
  }

  public static func fixed(_ output: Output) -> Self {
    Self { _, _, _ in output }
  }
}

public enum StructuredGenerationPipelineStatus: String, Equatable, Sendable {
  case accepted
  case rejected
  case fellBack
  case failed
}

public struct StructuredGenerationPipelineResult<Output: Sendable>: Sendable {
  public var candidate: StructuredGenerationCandidate<Output>?
  public var errorMessage: String?
  public var fallbackDecision: FallbackDecision<Output>?
  public var repairPlan: StructuredGenerationRepairPlan
  public var status: StructuredGenerationPipelineStatus
  public var validation: StructuredGenerationValidationResult

  public init(
    status: StructuredGenerationPipelineStatus,
    candidate: StructuredGenerationCandidate<Output>? = nil,
    validation: StructuredGenerationValidationResult = .accepted,
    repairPlan: StructuredGenerationRepairPlan = .none,
    fallbackDecision: FallbackDecision<Output>? = nil,
    errorMessage: String? = nil
  ) {
    self.candidate = candidate
    self.errorMessage = errorMessage
    self.fallbackDecision = fallbackDecision
    self.repairPlan = repairPlan
    self.status = status
    self.validation = validation
  }

  public var output: Output? {
    fallbackDecision?.output ?? candidate?.output
  }
}

extension StructuredGenerationPipelineResult: Equatable where Output: Equatable {}

public struct StructuredGenerationPipeline<Output: Sendable>: Sendable {
  public var errorToFallbackReason: @Sendable (any Error) -> FallbackReason
  public var fallbackPolicy: StructuredGenerationFallbackPolicy<Output>
  public var generate: @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Output>
  public var repairPolicy: StructuredGenerationRepairPolicy<Output>
  public var validator: StructuredGenerationValidator<Output>

  public init(
    generate: @escaping @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Output>,
    validator: StructuredGenerationValidator<Output> = .acceptAll,
    repairPolicy: StructuredGenerationRepairPolicy<Output> = .none,
    fallbackPolicy: StructuredGenerationFallbackPolicy<Output> = .none,
    errorToFallbackReason: @escaping @Sendable (any Error) -> FallbackReason = { error in
      if let error = error as? LLMError {
        return .providerError(error.message)
      }
      return .providerError(error.localizedDescription)
    }
  ) {
    self.errorToFallbackReason = errorToFallbackReason
    self.fallbackPolicy = fallbackPolicy
    self.generate = generate
    self.repairPolicy = repairPolicy
    self.validator = validator
  }

  public func run(
    prompt: CompiledPrompt,
    context: StructuredGenerationSourceContext = StructuredGenerationSourceContext(),
    evidence: @Sendable (Output) -> [EvidenceSpan] = { _ in [] },
    rawOutputDescription: @Sendable (Output) -> String? = { output in String(describing: output) }
  ) async -> StructuredGenerationPipelineResult<Output> {
    do {
      let generated = try await generate(prompt)
      let candidate = StructuredGenerationCandidate(
        generationCandidate: generated,
        evidence: evidence(generated.output),
        rawOutputDescription: rawOutputDescription(generated.output)
      )
      let validation = validator(candidate, in: context)

      guard validation.isAccepted else {
        let repairPlan = repairPolicy.plan(candidate, validation, .validationFailed)
        if let fallbackOutput = fallbackPolicy.resolve(.validationFailed, candidate, validation) {
          return StructuredGenerationPipelineResult(
            status: .fellBack,
            candidate: candidate,
            validation: validation,
            repairPlan: repairPlan,
            fallbackDecision: FallbackDecision(output: fallbackOutput, reason: .validationFailed)
          )
        }

        return StructuredGenerationPipelineResult(
          status: .rejected,
          candidate: candidate,
          validation: validation,
          repairPlan: repairPlan
        )
      }

      return StructuredGenerationPipelineResult(
        status: .accepted,
        candidate: candidate,
        validation: validation
      )
    } catch {
      let fallbackReason = errorToFallbackReason(error)
      let validation = StructuredGenerationValidationResult(
        issues: [
          ValidationIssue(
            id: "generation-failed",
            message: error.localizedDescription,
            severity: .error
          )
        ]
      )
      let repairPlan = repairPolicy.plan(nil, validation, fallbackReason)
      if let fallbackOutput = fallbackPolicy.resolve(fallbackReason, nil, validation) {
        return StructuredGenerationPipelineResult(
          status: .fellBack,
          validation: validation,
          repairPlan: repairPlan,
          fallbackDecision: FallbackDecision(output: fallbackOutput, reason: fallbackReason),
          errorMessage: error.localizedDescription
        )
      }

      return StructuredGenerationPipelineResult(
        status: .failed,
        validation: validation,
        repairPlan: repairPlan,
        errorMessage: error.localizedDescription
      )
    }
  }
}
