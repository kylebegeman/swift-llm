import Foundation
import SwiftLLM

public enum FoundationModelExecutionTarget: Equatable, Sendable {
  case automatic
  case onDevice
  case privateCloudCompute
  case providerPackage(String)
  case customLocal(String)

  public var diagnosticName: String {
    switch self {
    case .automatic:
      return "automatic"
    case .onDevice:
      return "onDevice"
    case .privateCloudCompute:
      return "privateCloudCompute"
    case let .providerPackage(identifier):
      return "providerPackage:\(identifier)"
    case let .customLocal(identifier):
      return "customLocal:\(identifier)"
    }
  }

  public var privacyMode: LLMPrivacyMode {
    switch self {
    case .automatic, .onDevice, .customLocal:
      return .localOnly
    case .privateCloudCompute:
      return .localWithUserSelectedContext
    case .providerPackage:
      return .externalOptIn
    }
  }

  public var defaultContextWindowTokens: Int? {
    switch self {
    case .onDevice:
      return FoundationModelDefaults.onDeviceContextWindowTokens
    case .privateCloudCompute:
      return FoundationModelDefaults.privateCloudContextWindowTokens
    case .automatic, .providerPackage, .customLocal:
      return nil
    }
  }

  public var requiresNetworkExecution: Bool {
    switch self {
    case .privateCloudCompute, .providerPackage:
      return true
    case .automatic, .customLocal, .onDevice:
      return false
    }
  }
}

public enum FoundationModelReasoningEffort: String, Equatable, Sendable {
  case disabled
  case low
  case medium
  case high
  case systemDefault
}

public enum FoundationModelQuotaStatus: Equatable, Sendable {
  case available(remainingRequests: Int? = nil)
  case exhausted(resetsAt: Date? = nil)
  case limited(resetsAt: Date? = nil)
  case notApplicable
  case unknown

  public var permitsGeneration: Bool {
    switch self {
    case .available, .notApplicable, .unknown:
      return true
    case .exhausted, .limited:
      return false
    }
  }
}

public struct FoundationModelRuntimeProfile: Equatable, Sendable {
  public var contextWindowTokens: Int?
  public var executionTarget: FoundationModelExecutionTarget
  public var quotaStatus: FoundationModelQuotaStatus
  public var reasoningEffort: FoundationModelReasoningEffort
  public var supportsDynamicContext: Bool
  public var supportsReasoning: Bool

  public init(
    executionTarget: FoundationModelExecutionTarget = .automatic,
    contextWindowTokens: Int? = nil,
    supportsReasoning: Bool = false,
    reasoningEffort: FoundationModelReasoningEffort = .systemDefault,
    quotaStatus: FoundationModelQuotaStatus = .unknown,
    supportsDynamicContext: Bool = false
  ) {
    self.contextWindowTokens = contextWindowTokens ?? executionTarget.defaultContextWindowTokens
    self.executionTarget = executionTarget
    self.quotaStatus = quotaStatus
    self.reasoningEffort = reasoningEffort
    self.supportsDynamicContext = supportsDynamicContext
    self.supportsReasoning = supportsReasoning
  }

  public static let onDevice = Self(
    executionTarget: .onDevice,
    contextWindowTokens: FoundationModelDefaults.onDeviceContextWindowTokens,
    supportsReasoning: false,
    reasoningEffort: .disabled,
    quotaStatus: .notApplicable,
    supportsDynamicContext: false
  )

  public static let privateCloudCompute = Self(
    executionTarget: .privateCloudCompute,
    contextWindowTokens: FoundationModelDefaults.privateCloudContextWindowTokens,
    supportsReasoning: true,
    reasoningEffort: .systemDefault,
    quotaStatus: .unknown,
    supportsDynamicContext: true
  )
}
