import Foundation
import SwiftLLM

public enum EvaluationSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}

public struct EvaluationIssue: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var message: String
  public var path: String?
  public var severity: EvaluationSeverity

  public init(
    id: String,
    message: String,
    severity: EvaluationSeverity = .error,
    path: String? = nil
  ) {
    self.id = id
    self.message = message
    self.path = path
    self.severity = severity
  }
}

public struct StructuredEvaluationAssertion<Output: Sendable>: Sendable {
  public var evaluate: @Sendable (Output) -> [EvaluationIssue]
  public var id: String

  public init(
    id: String,
    evaluate: @escaping @Sendable (Output) -> [EvaluationIssue]
  ) {
    self.evaluate = evaluate
    self.id = id
  }

  public func callAsFunction(_ output: Output) -> [EvaluationIssue] {
    evaluate(output)
  }
}

extension StructuredEvaluationAssertion {
  public static func predicate(
    id: String,
    message: String,
    path: String? = nil,
    severity: EvaluationSeverity = .error,
    isSatisfied: @escaping @Sendable (Output) -> Bool
  ) -> Self {
    Self(id: id) { output in
      guard isSatisfied(output) else {
        return [
          EvaluationIssue(
            id: id,
            message: message,
            severity: severity,
            path: path
          )
        ]
      }
      return []
    }
  }

  public static func nonEmptyString(
    _ value: @escaping @Sendable (Output) -> String,
    id: String,
    path: String
  ) -> Self {
    predicate(
      id: id,
      message: "Expected non-empty text.",
      path: path
    ) { output in
      !value(output).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  public static func maximumCount<Element>(
    _ values: @escaping @Sendable (Output) -> [Element],
    maximum: Int,
    id: String,
    path: String
  ) -> Self {
    Self(id: id) { output in
      let count = values(output).count
      guard count <= maximum else {
        return [
          EvaluationIssue(
            id: id,
            message: "Expected at most \(maximum) items but received \(count).",
            path: path
          )
        ]
      }
      return []
    }
  }

  public static func requiredText(
    _ value: @escaping @Sendable (Output) -> String,
    contains requiredText: String,
    id: String,
    path: String
  ) -> Self {
    predicate(
      id: id,
      message: "Expected text to contain \(requiredText).",
      path: path
    ) { output in
      value(output).localizedCaseInsensitiveContains(requiredText)
    }
  }
}

public struct StructuredOutputEvaluationResult<Output: Sendable>: Sendable {
  public var caseID: String
  public var issues: [EvaluationIssue]
  public var output: Output

  public init(
    caseID: String,
    output: Output,
    issues: [EvaluationIssue]
  ) {
    self.caseID = caseID
    self.issues = issues
    self.output = output
  }

  public var passed: Bool {
    !issues.contains { $0.severity == .error }
  }
}

extension StructuredOutputEvaluationResult: Equatable where Output: Equatable {}

public struct StructuredOutputEvaluator<Output: Sendable>: Sendable {
  public var assertions: [StructuredEvaluationAssertion<Output>]

  public init(assertions: [StructuredEvaluationAssertion<Output>]) {
    self.assertions = assertions
  }

  public func evaluate(
    caseID: String,
    output: Output
  ) -> StructuredOutputEvaluationResult<Output> {
    StructuredOutputEvaluationResult(
      caseID: caseID,
      output: output,
      issues: assertions.flatMap { $0(output) }
    )
  }
}

public struct EvaluationRunMetrics: Codable, Equatable, Sendable {
  public var cachedInputTokens: Int?
  public var durationMilliseconds: Double?
  public var estimatedInputTokens: Int?
  public var estimatedOutputTokens: Int?
  public var fallbackReason: String?
  public var inputChunkCount: Int?
  public var reasoningTokens: Int?
  public var retrievalSnippetCount: Int?
  public var validationIssueCount: Int?

  public init(
    estimatedInputTokens: Int? = nil,
    estimatedOutputTokens: Int? = nil,
    cachedInputTokens: Int? = nil,
    reasoningTokens: Int? = nil,
    durationMilliseconds: Double? = nil,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    fallbackReason: String? = nil,
    validationIssueCount: Int? = nil
  ) {
    self.cachedInputTokens = cachedInputTokens
    self.durationMilliseconds = durationMilliseconds
    self.estimatedInputTokens = estimatedInputTokens
    self.estimatedOutputTokens = estimatedOutputTokens
    self.fallbackReason = fallbackReason
    self.inputChunkCount = inputChunkCount
    self.reasoningTokens = reasoningTokens
    self.retrievalSnippetCount = retrievalSnippetCount
    self.validationIssueCount = validationIssueCount
  }

  public init(
    tokenUsage: LLMTokenUsage?,
    duration: TimeInterval? = nil,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    fallbackReason: String? = nil,
    validationIssueCount: Int? = nil
  ) {
    self.init(
      estimatedInputTokens: tokenUsage?.estimatedInputTokens,
      estimatedOutputTokens: tokenUsage?.estimatedOutputTokens,
      cachedInputTokens: tokenUsage?.cachedInputTokens,
      reasoningTokens: tokenUsage?.reasoningTokens,
      durationMilliseconds: duration.map { $0 * 1_000 },
      inputChunkCount: inputChunkCount,
      retrievalSnippetCount: retrievalSnippetCount,
      fallbackReason: fallbackReason,
      validationIssueCount: validationIssueCount
    )
  }

  public init(
    receipt: LLMRunReceipt,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    validationIssueCount: Int? = nil
  ) {
    self.init(
      estimatedInputTokens: receipt.tokenUsage?.estimatedInputTokens,
      estimatedOutputTokens: receipt.tokenUsage?.estimatedOutputTokens,
      cachedInputTokens: receipt.tokenUsage?.cachedInputTokens,
      reasoningTokens: receipt.tokenUsage?.reasoningTokens,
      durationMilliseconds: receipt.durationMilliseconds,
      inputChunkCount: inputChunkCount,
      retrievalSnippetCount: retrievalSnippetCount,
      fallbackReason: receipt.attempts.last(where: { $0.error?.fallbackReason != nil })?.error?.fallbackReason,
      validationIssueCount: validationIssueCount
    )
  }
}

public struct PromptEvaluationResultRecord: Codable, Equatable, Sendable {
  public var caseID: String
  public var failures: [String]
  public var output: String?
  public var passed: Bool

  public init(
    caseID: String,
    passed: Bool,
    failures: [String],
    output: String? = nil
  ) {
    self.caseID = caseID
    self.failures = failures
    self.output = output
    self.passed = passed
  }

  public init(
    result: PromptEvaluationResult,
    includeOutput: Bool = false
  ) {
    self.init(
      caseID: result.caseID,
      passed: result.passed,
      failures: result.failures,
      output: includeOutput ? result.output : nil
    )
  }
}

public struct PromptVersionEvaluationReport: Codable, Equatable, Identifiable, Sendable {
  public var caseResults: [PromptEvaluationResultRecord]
  public var createdAt: Date
  public var id: String
  public var metrics: EvaluationRunMetrics?
  public var promptID: String
  public var promptVersion: String
  public var storesRawOutputs: Bool

  public init(
    id: String = UUID().uuidString,
    promptID: String,
    promptVersion: String,
    caseResults: [PromptEvaluationResultRecord],
    metrics: EvaluationRunMetrics? = nil,
    storesRawOutputs: Bool = false,
    createdAt: Date = Date()
  ) {
    self.caseResults = caseResults
    self.createdAt = createdAt
    self.id = id
    self.metrics = metrics
    self.promptID = promptID
    self.promptVersion = promptVersion
    self.storesRawOutputs = storesRawOutputs
  }

  public init(
    prompt: PromptContract,
    results: [PromptEvaluationResult],
    metrics: EvaluationRunMetrics? = nil,
    includeOutputs: Bool = false,
    createdAt: Date = Date()
  ) {
    self.init(
      promptID: prompt.id,
      promptVersion: prompt.version,
      caseResults: results.map {
        PromptEvaluationResultRecord(result: $0, includeOutput: includeOutputs)
      },
      metrics: metrics,
      storesRawOutputs: includeOutputs,
      createdAt: createdAt
    )
  }

  public var passed: Bool {
    caseResults.allSatisfy(\.passed)
  }

  public func jsonData(prettyPrinted: Bool = true) throws -> Data {
    try JSONEncoder.evaluationReportEncoder(prettyPrinted: prettyPrinted).encode(self)
  }
}

public struct PromptVersionEvaluationMatrix: Codable, Equatable, Sendable {
  public var reports: [PromptVersionEvaluationReport]

  public init(reports: [PromptVersionEvaluationReport]) {
    self.reports = reports
  }

  public var passed: Bool {
    reports.allSatisfy(\.passed)
  }

  public var versions: [String] {
    reports.map(\.promptVersion)
  }
}

public struct ModelFallbackMatrixEntry: Codable, Equatable, Identifiable, Sendable {
  public var availability: String
  public var failedCaseCount: Int
  public var fallbackReason: String?
  public var id: String
  public var modelIdentifier: String?
  public var passedCaseCount: Int
  public var providerKind: String

  public init(
    providerKind: String,
    availability: String,
    passedCaseCount: Int,
    failedCaseCount: Int,
    modelIdentifier: String? = nil,
    fallbackReason: String? = nil
  ) {
    self.availability = availability
    self.failedCaseCount = failedCaseCount
    self.fallbackReason = fallbackReason
    self.id = [
      providerKind,
      modelIdentifier,
      availability,
      fallbackReason,
    ]
    .compactMap { $0 }
    .joined(separator: ":")
    self.modelIdentifier = modelIdentifier
    self.passedCaseCount = passedCaseCount
    self.providerKind = providerKind
  }
}

public struct ModelFallbackMatrix: Codable, Equatable, Sendable {
  public var entries: [ModelFallbackMatrixEntry]

  public init(entries: [ModelFallbackMatrixEntry]) {
    self.entries = entries
  }

  public var failedCaseCount: Int {
    entries.reduce(0) { $0 + $1.failedCaseCount }
  }

  public var passedCaseCount: Int {
    entries.reduce(0) { $0 + $1.passedCaseCount }
  }
}

public enum LocalDebugBundleContentPolicy: String, Codable, Equatable, Sendable {
  case redacted
  case includesRawOutputs
}

public struct LocalDebugBundle: Codable, Equatable, Identifiable, Sendable {
  public var contentPolicy: LocalDebugBundleContentPolicy
  public var createdAt: Date
  public var id: String
  public var modelFallbackMatrix: ModelFallbackMatrix?
  public var notes: String
  public var promptReports: [PromptVersionEvaluationReport]
  public var runReceipts: [LLMRunReceipt]

  public init(
    id: String = UUID().uuidString,
    promptReports: [PromptVersionEvaluationReport],
    modelFallbackMatrix: ModelFallbackMatrix? = nil,
    runReceipts: [LLMRunReceipt] = [],
    contentPolicy: LocalDebugBundleContentPolicy = .redacted,
    notes: String = "",
    createdAt: Date = Date()
  ) {
    self.contentPolicy = contentPolicy
    self.createdAt = createdAt
    self.id = id
    self.modelFallbackMatrix = modelFallbackMatrix
    self.notes = notes
    self.promptReports = promptReports
    self.runReceipts = runReceipts
  }

  public var passed: Bool {
    promptReports.allSatisfy(\.passed) &&
      (modelFallbackMatrix?.failedCaseCount ?? 0) == 0 &&
      runReceipts.allSatisfy { $0.outcome == .succeeded }
  }

  public func jsonData(prettyPrinted: Bool = true) throws -> Data {
    try JSONEncoder.evaluationReportEncoder(prettyPrinted: prettyPrinted).encode(self)
  }
}

private extension JSONEncoder {
  static func evaluationReportEncoder(prettyPrinted: Bool) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
      encoder.outputFormatting = [.sortedKeys]
    }
    return encoder
  }
}
