import Foundation
import SwiftLLM

// MARK: - Public Transport

/// HTTP request shape used by `AnthropicHTTPTransport`.
public struct AnthropicHTTPRequest: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var method: String
  public var url: URL

  public init(
    url: URL,
    method: String = "POST",
    headers: [String: String] = [:],
    body: Data = Data()
  ) {
    self.body = body
    self.headers = headers
    self.method = method
    self.url = url
  }

  public func urlRequest() -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    for (field, value) in headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    return request
  }
}

/// HTTP response shape returned by `AnthropicHTTPTransport`.
public struct AnthropicHTTPResponse: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    body: Data
  ) {
    self.body = body
    self.headers = headers
    self.statusCode = statusCode
  }
}

/// Streaming HTTP response that yields server-sent-event lines.
public struct AnthropicHTTPStreamResponse: Sendable {
  public var headers: [String: String]
  public var lines: AsyncThrowingStream<String, any Error>
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    lines: AsyncThrowingStream<String, any Error>
  ) {
    self.headers = headers
    self.lines = lines
    self.statusCode = statusCode
  }
}

/// Injectable Anthropic transport for production networking, tests, and app-specific policy.
public struct AnthropicHTTPTransport: Sendable {
  public var send: @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse
  public var stream: @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse

  public init(
    send: @escaping @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse,
    stream: (@Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse)? = nil
  ) {
    self.send = send
    self.stream = stream ?? { _ in
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "Anthropic streaming transport was not configured."
      )
    }
  }

  public static let live = Self(
    send: { request in
      try await liveSend(request)
    },
    stream: { request in
      try await liveStream(request)
    }
  )

  private static func liveSend(_ request: AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
    }
    return AnthropicHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      body: data
    )
  }

  private static func liveStream(_ request: AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse {
    let (bytes, response) = try await URLSession.shared.bytes(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
    }
    let lines = AsyncThrowingStream<String, any Error> { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines {
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
    return AnthropicHTTPStreamResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      lines: lines
    )
  }
}

// MARK: - Client

/// Anthropic Messages API adapter for the provider-neutral `LLMClient` protocol.
public struct AnthropicClient: LLMClient {
  private var apiKey: String
  public var apiVersion: String
  public var baseURL: URL
  public var defaultMaxTokens: Int
  public var model: String
  public var promptVersion: String
  public var transport: AnthropicHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01",
    defaultMaxTokens: Int = 1_024,
    promptVersion: String = "anthropic-messages-v1",
    transport: AnthropicHTTPTransport = .live
  ) {
    self.apiKey = apiKey
    self.apiVersion = apiVersion
    self.baseURL = baseURL
    self.defaultMaxTokens = defaultMaxTokens
    self.model = model
    self.promptVersion = promptVersion
    self.transport = transport
  }

  public var metadata: LLMProviderMetadata {
    LLMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "Anthropic",
      providerKind: .anthropic
    )
  }

  public var capabilities: LLMClientCapabilities {
    .anthropicMessages
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    let httpRequest = try messagesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    do {
      return try JSONDecoder.provider.decode(AnthropicMessageResponse.self, from: httpResponse.body)
        .llmResponse(metadata: metadata(for: request))
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "Anthropic response decoding failed: \(error.localizedDescription)"
      )
    }
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try messagesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw LLMClientError(
              reason: Self.errorReason(forStatusCode: streamResponse.statusCode, providerMessage: nil),
              statusCode: streamResponse.statusCode
            )
          }

          var streamState = AnthropicStreamState()
          var dataLines: [String] = []
          for try await line in streamResponse.lines {
            if line.isEmpty {
              try Self.processStreamDataLines(
                dataLines,
                streamState: &streamState,
                continuation: continuation
              )
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }

          try Self.processStreamDataLines(
            dataLines,
            streamState: &streamState,
            continuation: continuation
          )
          continuation.yield(
            .completed(
              LLMResponse(
                text: streamState.accumulatedText,
                toolCalls: streamState.toolCalls,
                finishReason: streamState.finishReason ?? .stop,
                tokenUsage: streamState.tokenUsage,
                model: model,
                metadata: metadata
              )
            )
          )
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

  func messagesHTTPRequest(
    for request: LLMRequest,
    stream: Bool
  ) throws -> AnthropicHTTPRequest {
    let body = AnthropicMessageRequest(
      model: model,
      maxTokens: request.parameters.maxOutputTokens ?? defaultMaxTokens,
      messages: try request.anthropicMessages(),
      system: request.anthropicSystem,
      temperature: request.parameters.temperature,
      topP: request.parameters.topP,
      stopSequences: request.parameters.stopSequences.isEmpty ? nil : request.parameters.stopSequences,
      tools: request.tools.isEmpty ? nil : request.tools.map(AnthropicTool.init),
      toolChoice: request.toolChoice.map(AnthropicToolChoice.init),
      stream: stream
    )
    let data = try JSONEncoder.provider.encode(body)
    return AnthropicHTTPRequest(
      url: baseURL.appendingPathComponent("messages"),
      headers: [
        "anthropic-version": apiVersion,
        "content-type": "application/json",
        "x-api-key": apiKey,
      ],
      body: data
    )
  }

  private func metadata(for request: LLMRequest) -> LLMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  private static func validate(_ response: AnthropicHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      let providerMessage = (try? JSONDecoder.provider.decode(AnthropicErrorPayload.self, from: response.body))
        .flatMap(\.error.message)
      throw LLMClientError(
        reason: errorReason(forStatusCode: response.statusCode, providerMessage: providerMessage),
        statusCode: response.statusCode,
        debugDescription: providerMessage
      )
    }
  }

  private static func errorReason(
    forStatusCode statusCode: Int,
    providerMessage: String?
  ) -> LLMClientErrorReason {
    switch statusCode {
    case 400:
      if providerMessage?.localizedCaseInsensitiveContains("context") == true {
        return .contextExceeded
      }
      return .badRequest
    case 401, 403:
      return .authentication
    case 408, 499:
      return .cancelled
    case 429:
      return .rateLimited
    case 500...599:
      return .unavailable
    default:
      return .provider(providerMessage ?? "Anthropic request failed with HTTP \(statusCode).")
    }
  }

  private static func processStreamDataLines(
    _ dataLines: [String],
    streamState: inout AnthropicStreamState,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation
  ) throws {
    // Anthropic streams tool arguments as JSON fragments, so state is required until a block stops.
    for dataLine in dataLines where dataLine != "[DONE]" && !dataLine.isEmpty {
      let event = try JSONDecoder.provider.decode(AnthropicStreamEvent.self, from: Data(dataLine.utf8))
      switch event.type {
      case "message_start":
        streamState.recordUsage(event.message?.usage)

      case "content_block_start":
        if let index = event.index,
           let contentBlock = event.contentBlock,
           contentBlock.type == "tool_use",
           let id = contentBlock.id,
           let name = contentBlock.name
        {
          streamState.startToolCall(
            index: index,
            id: id,
            name: name,
            input: contentBlock.input
          )
        }

      case "content_block_delta":
        if event.delta?.type == "text_delta",
           let text = event.delta?.text
        {
          streamState.accumulatedText += text
          continuation.yield(.textDelta(text))
        } else if event.delta?.type == "input_json_delta",
                  let index = event.index,
                  let partialJSON = event.delta?.partialJSON
        {
          streamState.appendToolInputDelta(partialJSON, index: index)
        }

      case "content_block_stop":
        if let index = event.index,
           let toolCall = streamState.finishToolCall(index: index)
        {
          continuation.yield(.toolCall(toolCall))
        }

      case "message_delta":
        streamState.recordUsage(event.usage)
        if let stopReason = event.delta?.stopReason {
          streamState.finishReason = stopReason.anthropicFinishReason
        }

      case "error":
        let message = event.error?.message ?? "Anthropic stream failed."
        throw LLMClientError(
          reason: .provider(message),
          debugDescription: message
        )

      default:
        break
      }
    }
  }
}

// MARK: - AnyLLMClient Convenience

extension AnyLLMClient {
  public static func anthropic(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01"
  ) -> Self {
    Self(
      AnthropicClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        apiVersion: apiVersion
      )
    )
  }
}

// MARK: - Request Encoding

private struct AnthropicMessageRequest: Encodable {
  var model: String
  var maxTokens: Int
  var messages: [AnthropicMessage]
  var system: String?
  var temperature: Double?
  var topP: Double?
  var stopSequences: [String]?
  var tools: [AnthropicTool]?
  var toolChoice: AnthropicToolChoice?
  var stream: Bool

  enum CodingKeys: String, CodingKey {
    case maxTokens = "max_tokens"
    case messages
    case model
    case stopSequences = "stop_sequences"
    case stream
    case system
    case temperature
    case toolChoice = "tool_choice"
    case tools
    case topP = "top_p"
  }
}

private struct AnthropicMessage: Encodable {
  var role: String
  var content: [AnthropicMessageContent]
}

private enum AnthropicMessageContent: Encodable {
  case text(String)
  case toolResult(AnthropicToolResultContent)
  case toolUse(AnthropicToolUseContent)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case let .text(text):
      try AnthropicTextContent(text: text).encode(to: encoder)
    case let .toolResult(result):
      try result.encode(to: encoder)
    case let .toolUse(toolUse):
      try toolUse.encode(to: encoder)
    }
  }
}

private struct AnthropicTextContent: Encodable {
  var text: String
  var type = "text"
}

private struct AnthropicToolUseContent: Encodable {
  var id: String
  var input: JSONValue
  var name: String
  var type = "tool_use"

  init(_ toolCall: LLMToolCall) throws {
    self.id = toolCall.id
    self.input = try toolCall.argumentsValue()
    self.name = toolCall.name
  }
}

private struct AnthropicToolResultContent: Encodable {
  var content: String
  var isError: Bool?
  var toolUseID: String
  var type = "tool_result"

  init(message: LLMMessage) throws {
    guard let toolCallID = message.toolCallID,
          !toolCallID.isEmpty
    else {
      throw LLMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic tool result messages require a non-empty toolCallID."
      )
    }
    self.content = message.content
    self.isError = message.toolResultIsError ? true : nil
    self.toolUseID = toolCallID
  }

  enum CodingKeys: String, CodingKey {
    case content
    case isError = "is_error"
    case toolUseID = "tool_use_id"
    case type
  }
}

private struct AnthropicTool: Encodable {
  var name: String
  var description: String
  var inputSchema: JSONValue

  init(_ definition: LLMToolDefinition) {
    self.description = definition.description
    self.inputSchema = definition.inputSchema
    self.name = definition.name
  }

  enum CodingKeys: String, CodingKey {
    case description
    case inputSchema = "input_schema"
    case name
  }
}

private enum AnthropicToolChoice: Encodable {
  case auto
  case none
  case required
  case tool(String)

  init(_ choice: LLMToolChoice) {
    switch choice {
    case .auto:
      self = .auto
    case .none:
      self = .none
    case .required:
      self = .required
    case let .tool(name):
      self = .tool(name)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .auto:
      try container.encode("auto", forKey: .type)
    case .none:
      try container.encode("none", forKey: .type)
    case .required:
      try container.encode("any", forKey: .type)
    case let .tool(name):
      try container.encode("tool", forKey: .type)
      try container.encode(name, forKey: .name)
    }
  }

  enum CodingKeys: String, CodingKey {
    case name
    case type
  }
}

// MARK: - Response Decoding

private struct AnthropicMessageResponse: Decodable {
  var content: [AnthropicContentBlock]
  var id: String
  var model: String?
  var stopReason: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case content
    case id
    case model
    case stopReason = "stop_reason"
    case usage
  }

  func llmResponse(metadata: LLMProviderMetadata) -> LLMResponse {
    let text = content.compactMap(\.text).joined(separator: "\n")
    return LLMResponse(
      id: id,
      text: text,
      toolCalls: content.compactMap(\.toolCall),
      finishReason: mappedFinishReason,
      tokenUsage: usage?.tokenUsage,
      model: model ?? metadata.modelIdentifier,
      metadata: metadata
    )
  }

  private var mappedFinishReason: LLMFinishReason? {
    stopReason?.anthropicFinishReason
  }
}

private struct AnthropicContentBlock: Decodable {
  var id: String?
  var input: JSONValue?
  var name: String?
  var text: String?
  var type: String

  var toolCall: LLMToolCall? {
    guard type == "tool_use",
          let id,
          let name
    else { return nil }
    let argumentsData = (try? JSONEncoder.provider.encode(input ?? .object([:]))) ?? Data("{}".utf8)
    return LLMToolCall(
      id: id,
      name: name,
      argumentsJSON: String(decoding: argumentsData, as: UTF8.self)
    )
  }
}

private struct AnthropicUsage: Decodable {
  var inputTokens: Int?
  var outputTokens: Int?

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }

  var tokenUsage: LLMTokenUsage {
    LLMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens
    )
  }
}

private struct AnthropicStreamEvent: Decodable {
  var contentBlock: AnthropicContentBlock?
  var delta: AnthropicStreamDelta?
  var error: AnthropicProviderError?
  var index: Int?
  var message: AnthropicStreamMessage?
  var type: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case contentBlock = "content_block"
    case delta
    case error
    case index
    case message
    case type
    case usage
  }
}

private struct AnthropicStreamDelta: Decodable {
  var partialJSON: String?
  var stopReason: String?
  var text: String?
  var type: String?

  enum CodingKeys: String, CodingKey {
    case partialJSON = "partial_json"
    case stopReason = "stop_reason"
    case text
    case type
  }
}

private struct AnthropicStreamMessage: Decodable {
  var usage: AnthropicUsage?
}

private struct AnthropicErrorPayload: Decodable {
  var error: AnthropicProviderError
}

private struct AnthropicProviderError: Decodable {
  var message: String?
}

// MARK: - Stream State

private struct AnthropicStreamState {
  var accumulatedText = ""
  var finishReason: LLMFinishReason?
  var inputTokens: Int?
  var outputTokens: Int?
  private var completedToolCalls: [LLMToolCall] = []
  private var pendingToolCalls: [Int: PendingAnthropicToolCall] = [:]

  var toolCalls: [LLMToolCall] {
    completedToolCalls
  }

  var tokenUsage: LLMTokenUsage? {
    guard inputTokens != nil || outputTokens != nil else { return nil }
    return LLMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens
    )
  }

  mutating func recordUsage(_ usage: AnthropicUsage?) {
    if let inputTokens = usage?.inputTokens {
      self.inputTokens = inputTokens
    }
    if let outputTokens = usage?.outputTokens {
      self.outputTokens = outputTokens
    }
  }

  mutating func startToolCall(
    index: Int,
    id: String,
    name: String,
    input: JSONValue?
  ) {
    let inputJSON = input.flatMap { input in
      try? JSONEncoder.provider.encode(input)
    }
    .map { String(decoding: $0, as: UTF8.self) }
    pendingToolCalls[index] = PendingAnthropicToolCall(
      id: id,
      initialArgumentsJSON: inputJSON ?? "{}",
      name: name
    )
  }

  mutating func appendToolInputDelta(
    _ partialJSON: String,
    index: Int
  ) {
    pendingToolCalls[index]?.partialArgumentsJSON += partialJSON
  }

  mutating func finishToolCall(index: Int) -> LLMToolCall? {
    guard let pendingToolCall = pendingToolCalls.removeValue(forKey: index) else {
      return nil
    }
    let toolCall = pendingToolCall.toolCall
    completedToolCalls.append(toolCall)
    return toolCall
  }
}

private struct PendingAnthropicToolCall {
  var id: String
  var initialArgumentsJSON: String
  var name: String
  var partialArgumentsJSON = ""

  var toolCall: LLMToolCall {
    LLMToolCall(
      id: id,
      name: name,
      argumentsJSON: partialArgumentsJSON.isEmpty ? initialArgumentsJSON : partialArgumentsJSON
    )
  }
}

// MARK: - Request Mapping

private extension LLMRequest {
  func anthropicMessages() throws -> [AnthropicMessage] {
    let conversationalMessages = messages.filter { $0.role != .system && $0.role != .developer }
    var anthropicMessages: [AnthropicMessage] = []
    var index = conversationalMessages.startIndex

    while index < conversationalMessages.endIndex {
      let message = conversationalMessages[index]

      if message.role == .tool {
        var content = try message.anthropicToolResultContent
        index = conversationalMessages.index(after: index)

        while index < conversationalMessages.endIndex,
              conversationalMessages[index].role == .tool
        {
          content.append(contentsOf: try conversationalMessages[index].anthropicToolResultContent)
          index = conversationalMessages.index(after: index)
        }

        if index < conversationalMessages.endIndex,
           conversationalMessages[index].role == .user
        {
          let userMessage = conversationalMessages[index]
          if !userMessage.content.isEmpty {
            content.append(.text(userMessage.content))
          }
          index = conversationalMessages.index(after: index)
        }

        anthropicMessages.append(AnthropicMessage(role: "user", content: content))
      } else {
        anthropicMessages.append(
          AnthropicMessage(
            role: message.role.anthropicRole,
            content: try message.anthropicContent
          )
        )
        index = conversationalMessages.index(after: index)
      }
    }

    return anthropicMessages.isEmpty
      ? [AnthropicMessage(role: "user", content: [.text("")])]
      : anthropicMessages
  }

  var anthropicSystem: String? {
    let messageInstructions = messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    let responseInstructions = responseFormat.anthropicSystemInstructions
    let system = [instructions, messageInstructions, responseInstructions]
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: "\n\n")
    return system.isEmpty ? nil : system
  }
}

private extension LLMMessage {
  var anthropicContent: [AnthropicMessageContent] {
    get throws {
      switch role {
      case .assistant:
        var content: [AnthropicMessageContent] = []
        if !self.content.isEmpty {
          content.append(.text(self.content))
        }
        content.append(contentsOf: try toolCalls.map { .toolUse(try AnthropicToolUseContent($0)) })
        return content.isEmpty ? [.text("")] : content
      case .tool:
        return try anthropicToolResultContent
      case .developer, .system, .user:
        return [.text(content)]
      }
    }
  }

  var anthropicToolResultContent: [AnthropicMessageContent] {
    get throws {
      [.toolResult(try AnthropicToolResultContent(message: self))]
    }
  }
}

private extension LLMToolCall {
  func argumentsValue() throws -> JSONValue {
    guard !argumentsJSON.isEmpty,
          let data = argumentsJSON.data(using: .utf8)
    else { return .object([:]) }

    do {
      return try JSONDecoder.provider.decode(JSONValue.self, from: data)
    } catch {
      throw LLMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic tool call arguments must be valid JSON."
      )
    }
  }
}

private extension LLMMessageRole {
  var anthropicRole: String {
    switch self {
    case .assistant:
      return "assistant"
    case .developer, .system, .tool, .user:
      return "user"
    }
  }
}

private extension String {
  var anthropicFinishReason: LLMFinishReason {
    switch self {
    case "end_turn", "stop_sequence":
      return .stop
    case "max_tokens":
      return .length
    case "tool_use":
      return .toolCalls
    default:
      return .unknown
    }
  }
}

private extension LLMResponseFormat {
  var anthropicSystemInstructions: String? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return "Return only valid JSON."
    case let .jsonSchema(schema):
      let encodedSchema = (try? JSONEncoder.provider.encode(schema.schema))
        .map { String(decoding: $0, as: UTF8.self) }
        ?? "{}"
      return """
      Return only valid JSON matching this schema.
      Schema name: \(schema.name)
      \(schema.description.map { "Description: \($0)\n" } ?? "")Schema:
      \(encodedSchema)
      """
    }
  }
}

// MARK: - JSON Coding

private extension JSONDecoder {
  static var provider: JSONDecoder {
    JSONDecoder()
  }
}

private extension JSONEncoder {
  static var provider: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
  response.allHeaderFields.reduce(into: [:]) { headers, field in
    if let key = field.key as? String,
       let value = field.value as? String
    {
      headers[key] = value
    }
  }
}
