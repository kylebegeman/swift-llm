import Foundation
import SwiftLLM

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
