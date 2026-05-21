import Foundation
import SwiftLLM

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

public struct AnthropicHTTPTransport: Sendable {
  public var send: @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse

  public init(
    send: @escaping @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse
  ) {
    self.send = send
  }

  public static let live = Self { request in
    let (data, response) = try await URLSession.shared.data(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
    }
    return AnthropicHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: httpResponse.allHeaderFields.reduce(into: [:]) { headers, field in
        if let key = field.key as? String,
           let value = field.value as? String
        {
          headers[key] = value
        }
      },
      body: data
    )
  }
}

public struct AnthropicClient: LLMClient {
  public var apiKey: String
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

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    let httpRequest = try messagesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    do {
      return try JSONDecoder.provider.decode(AnthropicMessageResponse.self, from: httpResponse.body)
        .llmResponse(metadata: metadata)
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "Anthropic response decoding failed: \(error.localizedDescription)"
      )
    }
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try messagesHTTPRequest(for: request, stream: true)
          let (bytes, response) = try await URLSession.shared.bytes(for: httpRequest.urlRequest())
          guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
          }
          guard 200..<300 ~= httpResponse.statusCode else {
            throw LLMClientError(
              reason: Self.errorReason(forStatusCode: httpResponse.statusCode, providerMessage: nil),
              statusCode: httpResponse.statusCode
            )
          }

          var accumulatedText = ""
          var dataLines: [String] = []
          for try await line in bytes.lines {
            if line.isEmpty {
              try Self.processStreamDataLines(
                dataLines,
                accumulatedText: &accumulatedText,
                continuation: continuation
              )
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }

          try Self.processStreamDataLines(
            dataLines,
            accumulatedText: &accumulatedText,
            continuation: continuation
          )
          continuation.yield(
            .completed(
              LLMResponse(
                text: accumulatedText,
                finishReason: .stop,
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
      messages: request.anthropicMessages,
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
    accumulatedText: inout String,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation
  ) throws {
    for dataLine in dataLines where dataLine != "[DONE]" && !dataLine.isEmpty {
      let event = try JSONDecoder.provider.decode(AnthropicStreamEvent.self, from: Data(dataLine.utf8))
      if event.type == "content_block_delta",
         event.delta?.type == "text_delta",
         let text = event.delta?.text
      {
        accumulatedText += text
        continuation.yield(.textDelta(text))
      }
    }
  }
}

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

private struct AnthropicMessage: Codable {
  var role: String
  var content: String
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
    let text = content.compactMap(\.text).joined()
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
    switch stopReason {
    case "end_turn", "stop_sequence":
      return .stop
    case "max_tokens":
      return .length
    case "tool_use":
      return .toolCalls
    case nil:
      return nil
    default:
      return .unknown
    }
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
  var delta: AnthropicStreamDelta?
  var type: String?
}

private struct AnthropicStreamDelta: Decodable {
  var text: String?
  var type: String?
}

private struct AnthropicErrorPayload: Decodable {
  var error: AnthropicProviderError
}

private struct AnthropicProviderError: Decodable {
  var message: String?
}

private extension LLMRequest {
  var anthropicMessages: [AnthropicMessage] {
    let messages = messages
      .filter { $0.role != .system && $0.role != .developer }
      .map { message in
        AnthropicMessage(
          role: message.role.anthropicRole,
          content: message.anthropicContent
        )
      }
    return messages.isEmpty ? [AnthropicMessage(role: "user", content: "")] : messages
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
  var anthropicContent: String {
    switch role {
    case .tool:
      return "Tool result\(toolCallID.map { " \($0)" } ?? ""):\n\(content)"
    case .assistant, .developer, .system, .user:
      return content
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
