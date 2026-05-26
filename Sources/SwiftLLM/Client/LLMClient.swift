import Foundation

/// A provider-neutral JSON value used for schemas, tool arguments, and other
/// request/response shapes that must stay dependency-free in the core target.
public indirect enum JSONValue: Equatable, Sendable {
  case array([JSONValue])
  case bool(Bool)
  case null
  case number(Double)
  case object([String: JSONValue])
  case string(String)
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .array(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    case let .number(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    case let .string(value):
      try container.encode(value)
    }
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(value)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .number(Double(value))
  }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

public enum LLMMessageRole: String, Codable, Equatable, Sendable {
  case assistant
  case developer
  case system
  case tool
  case user
}

/// A single provider-neutral conversation message.
///
/// The type carries both normal chat content and native tool-call history so
/// adapters can round-trip provider tool messages without app code learning each
/// provider's transport shape.
public struct LLMMessage: Codable, Equatable, Sendable {
  public var content: String
  public var name: String?
  public var role: LLMMessageRole
  public var toolCalls: [LLMToolCall]
  public var toolCallID: String?
  public var toolResultIsError: Bool

  public init(
    role: LLMMessageRole,
    content: String,
    name: String? = nil,
    toolCallID: String? = nil,
    toolCalls: [LLMToolCall] = [],
    toolResultIsError: Bool = false
  ) {
    self.content = content
    self.name = name
    self.role = role
    self.toolCalls = toolCalls
    self.toolCallID = toolCallID
    self.toolResultIsError = toolResultIsError
  }

  public static func assistant(
    _ content: String,
    toolCalls: [LLMToolCall] = []
  ) -> Self {
    Self(role: .assistant, content: content, toolCalls: toolCalls)
  }

  public static func developer(_ content: String) -> Self {
    Self(role: .developer, content: content)
  }

  public static func system(_ content: String) -> Self {
    Self(role: .system, content: content)
  }

  public static func tool(
    _ content: String,
    toolCallID: String,
    isError: Bool = false
  ) -> Self {
    Self(
      role: .tool,
      content: content,
      toolCallID: toolCallID,
      toolResultIsError: isError
    )
  }

  public static func user(_ content: String) -> Self {
    Self(role: .user, content: content)
  }

  // Keep default tool fields optional on the wire so older persisted messages remain decodable.
  enum CodingKeys: String, CodingKey {
    case content
    case name
    case role
    case toolCallID
    case toolCalls
    case toolResultIsError
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.content = try container.decode(String.self, forKey: .content)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.role = try container.decode(LLMMessageRole.self, forKey: .role)
    self.toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
    self.toolCalls = try container.decodeIfPresent([LLMToolCall].self, forKey: .toolCalls) ?? []
    self.toolResultIsError = try container.decodeIfPresent(Bool.self, forKey: .toolResultIsError) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(content, forKey: .content)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encode(role, forKey: .role)
    try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    if !toolCalls.isEmpty {
      try container.encode(toolCalls, forKey: .toolCalls)
    }
    if toolResultIsError {
      try container.encode(toolResultIsError, forKey: .toolResultIsError)
    }
  }
}

/// Sampling and output controls shared by provider adapters.
public struct LLMGenerationParameters: Equatable, Sendable {
  public var maxOutputTokens: Int?
  public var stopSequences: [String]
  public var temperature: Double?
  public var topP: Double?

  public init(
    temperature: Double? = nil,
    maxOutputTokens: Int? = nil,
    topP: Double? = nil,
    stopSequences: [String] = []
  ) {
    self.maxOutputTokens = maxOutputTokens
    self.stopSequences = stopSequences
    self.temperature = temperature
    self.topP = topP
  }

  public static let deterministic = Self(
    temperature: 0,
    maxOutputTokens: nil,
    topP: nil,
    stopSequences: []
  )
}

/// A JSON schema request that can be translated into provider-native structured
/// output where supported, or prompt instructions where it is not.
public struct LLMJSONSchema: Equatable, Sendable {
  public var description: String?
  public var name: String
  public var schema: JSONValue
  public var strict: Bool

  public init(
    name: String,
    description: String? = nil,
    schema: JSONValue,
    strict: Bool = true
  ) {
    self.description = description
    self.name = name
    self.schema = schema
    self.strict = strict
  }
}

public enum LLMResponseFormat: Equatable, Sendable {
  case jsonObject
  case jsonSchema(LLMJSONSchema)
  case text
}

/// Provider-neutral definition for a callable model tool.
public struct LLMToolDefinition: Equatable, Sendable {
  public var description: String
  public var inputSchema: JSONValue
  public var name: String
  public var strict: Bool

  public init(
    name: String,
    description: String,
    inputSchema: JSONValue,
    strict: Bool = true
  ) {
    self.description = description
    self.inputSchema = inputSchema
    self.name = name
    self.strict = strict
  }
}

public enum LLMToolChoice: Equatable, Sendable {
  case auto
  case none
  case required
  case tool(String)
}

/// A tool call emitted by a model.
public struct LLMToolCall: Codable, Equatable, Identifiable, Sendable {
  public var argumentsJSON: String
  public var id: String
  public var name: String

  public init(
    id: String,
    name: String,
    argumentsJSON: String
  ) {
    self.argumentsJSON = argumentsJSON
    self.id = id
    self.name = name
  }
}

/// A complete provider-neutral generation request.
public struct LLMRequest: Equatable, Sendable {
  public var contextPlan: LLMContextPlan?
  public var instructions: String?
  public var messages: [LLMMessage]
  public var metadata: [String: String]
  public var parameters: LLMGenerationParameters
  public var responseFormat: LLMResponseFormat
  public var toolChoice: LLMToolChoice?
  public var tools: [LLMToolDefinition]

  public init(
    instructions: String? = nil,
    messages: [LLMMessage],
    responseFormat: LLMResponseFormat = .text,
    tools: [LLMToolDefinition] = [],
    toolChoice: LLMToolChoice? = nil,
    parameters: LLMGenerationParameters = LLMGenerationParameters(),
    contextPlan: LLMContextPlan? = nil,
    metadata: [String: String] = [:]
  ) {
    self.contextPlan = contextPlan
    self.instructions = instructions
    self.messages = messages
    self.metadata = metadata
    self.parameters = parameters
    self.responseFormat = responseFormat
    self.toolChoice = toolChoice
    self.tools = tools
  }

  public init(
    prompt: CompiledPrompt,
    responseFormat: LLMResponseFormat = .text,
    tools: [LLMToolDefinition] = [],
    toolChoice: LLMToolChoice? = nil,
    parameters: LLMGenerationParameters = LLMGenerationParameters(),
    metadata: [String: String] = [:]
  ) {
    self.init(
      instructions: prompt.systemInstructions,
      messages: [.user(prompt.userPrompt)],
      responseFormat: responseFormat,
      tools: tools,
      toolChoice: toolChoice,
      parameters: parameters,
      contextPlan: prompt.contextPlan,
      metadata: metadata.merging([
        "promptID": prompt.contract.id,
        "promptVersion": prompt.contract.version,
      ]) { current, _ in current }
    )
  }
}

public enum LLMFinishReason: String, Equatable, Sendable {
  case contentFilter
  case error
  case length
  case stop
  case toolCalls
  case unknown
}

/// A completed provider-neutral generation response.
public struct LLMResponse: Equatable, Identifiable, Sendable {
  public var finishReason: LLMFinishReason?
  public var id: String
  public var message: LLMMessage
  public var metadata: LLMProviderMetadata
  public var model: String?
  public var text: String
  public var tokenUsage: LLMTokenUsage?
  public var toolCalls: [LLMToolCall]

  public init(
    id: String = UUID().uuidString,
    text: String,
    message: LLMMessage? = nil,
    toolCalls: [LLMToolCall] = [],
    finishReason: LLMFinishReason? = nil,
    tokenUsage: LLMTokenUsage? = nil,
    model: String? = nil,
    metadata: LLMProviderMetadata
  ) {
    self.finishReason = finishReason
    self.id = id
    self.message = message ?? .assistant(text, toolCalls: toolCalls)
    self.metadata = metadata
    self.model = model
    self.text = text
    self.tokenUsage = tokenUsage
    self.toolCalls = toolCalls
  }

  public var candidate: GenerationCandidate<String> {
    GenerationCandidate(
      output: text,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

/// Streaming lifecycle events emitted by an `LLMClient`.
public enum LLMStreamEvent: Equatable, Sendable {
  case completed(LLMResponse)
  case started(LLMProviderMetadata)
  case textDelta(String)
  case toolCall(LLMToolCall)
}

public enum LLMClientErrorReason: Equatable, Sendable {
  case authentication
  case badRequest
  case cancelled
  case contextExceeded
  case decoding
  case guardrailViolation
  case network
  case provider(String)
  case rateLimited
  case unavailable
  case unsupported
}

public struct LLMClientError: LLMFallbackClassifiableError, Equatable, LocalizedError, Sendable {
  public var debugDescription: String?
  public var reason: LLMClientErrorReason
  public var statusCode: Int?

  public init(
    reason: LLMClientErrorReason,
    statusCode: Int? = nil,
    debugDescription: String? = nil
  ) {
    self.debugDescription = debugDescription
    self.reason = reason
    self.statusCode = statusCode
  }

  public var errorDescription: String? {
    switch reason {
    case .authentication:
      return "The provider rejected the configured credentials."
    case .badRequest:
      return "The provider rejected the request."
    case .cancelled:
      return "The generation request was cancelled."
    case .contextExceeded:
      return "The request exceeded the model context window."
    case .decoding:
      return "The provider response could not be decoded."
    case .guardrailViolation:
      return "The provider rejected the request or response for safety reasons."
    case .network:
      return "The provider request failed before a response was received."
    case let .provider(message):
      return message
    case .rateLimited:
      return "The provider rate-limited the request."
    case .unavailable:
      return "The provider is unavailable."
    case .unsupported:
      return "The provider does not support this request."
    }
  }

  public var fallbackReason: FallbackReason {
    switch reason {
    case .authentication, .badRequest, .provider:
      return .providerError(debugDescription ?? errorDescription ?? "Provider error.")
    case .network:
      return .unavailable
    case .cancelled:
      return .providerError("Request cancelled.")
    case .contextExceeded:
      return .contextExceeded
    case .decoding:
      return .decodingFailed
    case .guardrailViolation:
      return .guardrailViolation
    case .rateLimited:
      return .rateLimited
    case .unavailable:
      return .unavailable
    case .unsupported:
      return .unsupported
    }
  }
}

/// A common async interface for local and provider-backed language model clients.
public protocol LLMClient: Sendable {
  var capabilities: LLMClientCapabilities { get }
  var metadata: LLMProviderMetadata { get }

  func respond(to request: LLMRequest) async throws -> LLMResponse
  func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>
}

extension LLMClient {
  public var capabilities: LLMClientCapabilities {
    .broadlyCompatible
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = self.metadata
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let response = try await respond(to: request)
          continuation.yield(.textDelta(response.text))
          for toolCall in response.toolCalls {
            continuation.yield(.toolCall(toolCall))
          }
          continuation.yield(.completed(response))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

/// Type-erased wrapper that lets routers and pipelines store heterogeneous clients.
public struct AnyLLMClient: LLMClient {
  private var respondHandler: @Sendable (LLMRequest) async throws -> LLMResponse
  private var streamHandler: @Sendable (LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>

  public var capabilities: LLMClientCapabilities
  public var metadata: LLMProviderMetadata

  public init<C: LLMClient>(_ client: C) {
    self.capabilities = client.capabilities
    self.metadata = client.metadata
    self.respondHandler = { request in
      try await client.respond(to: request)
    }
    self.streamHandler = { request in
      client.stream(to: request)
    }
  }

  public init(
    metadata: LLMProviderMetadata,
    capabilities: LLMClientCapabilities = .broadlyCompatible,
    respond: @escaping @Sendable (LLMRequest) async throws -> LLMResponse,
    stream: (@Sendable (LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>)? = nil
  ) {
    self.capabilities = capabilities
    self.metadata = metadata
    self.respondHandler = respond
    if let stream {
      self.streamHandler = stream
    } else {
      self.streamHandler = { request in
        AsyncThrowingStream { continuation in
          continuation.yield(.started(metadata))
          let task = Task {
            do {
              let response = try await respond(request)
              continuation.yield(.textDelta(response.text))
              for toolCall in response.toolCalls {
                continuation.yield(.toolCall(toolCall))
              }
              continuation.yield(.completed(response))
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in
            task.cancel()
          }
        }
      }
    }
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    try await respondHandler(request)
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    streamHandler(request)
  }

  public static func testDouble(
    modelIdentifier: String = "test-double",
    promptVersion: String = "test",
    respond: @escaping @Sendable (LLMRequest) async throws -> String
  ) -> Self {
    let metadata = LLMProviderMetadata(
      modelIdentifier: modelIdentifier,
      privacyMode: .localOnly,
      promptVersion: promptVersion,
      providerDisplayName: "Test Double",
      providerKind: .testDouble
    )
    return Self(metadata: metadata, capabilities: .deterministicLocal) { request in
      LLMResponse(
        text: try await respond(request),
        metadata: metadata
      )
    }
  }
}
