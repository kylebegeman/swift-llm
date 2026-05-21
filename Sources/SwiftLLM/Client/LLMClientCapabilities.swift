public enum LLMCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case jsonObjectResponse
  case jsonSchemaResponse
  case nativeJSONSchemaResponse
  case stopSequences
  case streaming
  case temperature
  case toolResults
  case tools
  case topP
}

public struct LLMClientCapabilities: Equatable, Sendable {
  public var contextWindowTokens: Int?
  public var supportedFeatures: Set<LLMCapability>

  public init(
    supportedFeatures: Set<LLMCapability> = Set(LLMCapability.allCases),
    contextWindowTokens: Int? = nil
  ) {
    self.contextWindowTokens = contextWindowTokens
    self.supportedFeatures = supportedFeatures
  }

  public func supports(_ capability: LLMCapability) -> Bool {
    supportedFeatures.contains(capability)
  }

  public func unsupportedCapabilities(
    for request: LLMRequest,
    streaming: Bool = false
  ) -> [LLMCapability] {
    request.requiredCapabilities(streaming: streaming)
      .filter { !supports($0) }
      .sorted { $0.rawValue < $1.rawValue }
  }

  public static let broadlyCompatible = Self()

  public static let deterministicLocal = Self(
    supportedFeatures: [
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .stopSequences,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )

  public static let foundationModelsProviderNeutral = Self(
    supportedFeatures: [
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .streaming,
      .temperature,
    ],
    contextWindowTokens: 4_096
  )

  public static let openAIResponses = Self(
    supportedFeatures: [
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .nativeJSONSchemaResponse,
      .stopSequences,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )

  public static let anthropicMessages = Self(
    supportedFeatures: [
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .stopSequences,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )
}

extension LLMRequest {
  public func requiredCapabilities(streaming: Bool = false) -> Set<LLMCapability> {
    var capabilities: Set<LLMCapability> = []

    if streaming {
      capabilities.insert(.streaming)
    }

    switch responseFormat {
    case .jsonObject:
      capabilities.insert(.jsonObjectResponse)
    case .jsonSchema:
      capabilities.insert(.jsonSchemaResponse)
    case .text:
      break
    }

    if !tools.isEmpty ||
      toolChoice?.requiresToolSupport == true ||
      messages.contains(where: { !$0.toolCalls.isEmpty })
    {
      capabilities.insert(.tools)
    }

    if messages.contains(where: { $0.role == .tool }) {
      capabilities.insert(.toolResults)
    }

    if parameters.temperature != nil {
      capabilities.insert(.temperature)
    }

    if parameters.topP != nil {
      capabilities.insert(.topP)
    }

    if !parameters.stopSequences.isEmpty {
      capabilities.insert(.stopSequences)
    }

    return capabilities
  }
}

extension LLMToolChoice {
  public var requiresToolSupport: Bool {
    switch self {
    case .auto, .none:
      return false
    case .required, .tool:
      return true
    }
  }
}
