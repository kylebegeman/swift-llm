import Foundation
import SwiftLLM

public struct OpenAIHTTPRequest: Sendable {
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

public struct OpenAIHTTPResponse: Sendable {
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

public struct OpenAIHTTPStreamResponse: Sendable {
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

public struct OpenAIHTTPTransport: Sendable {
  public var send: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse
  public var stream: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse

  public init(
    send: @escaping @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse,
    stream: (@Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse)? = nil
  ) {
    self.send = send
    self.stream = stream ?? { _ in
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "OpenAI streaming transport was not configured."
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

  private static func liveSend(_ request: OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
    }
    return OpenAIHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      body: data
    )
  }

  private static func liveStream(_ request: OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse {
    let (bytes, response) = try await URLSession.shared.bytes(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
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
    return OpenAIHTTPStreamResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      lines: lines
    )
  }
}

public struct OpenAIClient: LLMClient {
  private var apiKey: String
  public var baseURL: URL
  public var model: String
  public var organizationID: String?
  public var projectID: String?
  public var promptVersion: String
  public var transport: OpenAIHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil,
    promptVersion: String = "openai-responses-v1",
    transport: OpenAIHTTPTransport = .live
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.model = model
    self.organizationID = organizationID
    self.projectID = projectID
    self.promptVersion = promptVersion
    self.transport = transport
  }

  public var metadata: LLMProviderMetadata {
    LLMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "OpenAI",
      providerKind: .openAI
    )
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    let httpRequest = try responsesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    do {
      return try JSONDecoder.provider.decode(OpenAIResponsePayload.self, from: httpResponse.body)
        .llmResponse(metadata: metadata(for: request))
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "OpenAI response decoding failed: \(error.localizedDescription)"
      )
    }
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try responsesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw LLMClientError(
              reason: Self.errorReason(forStatusCode: streamResponse.statusCode, providerMessage: nil),
              statusCode: streamResponse.statusCode
            )
          }

          var accumulatedText = ""
          var completedResponse: LLMResponse?
          var dataLines: [String] = []
          for try await line in streamResponse.lines {
            if line.isEmpty {
              try Self.processStreamDataLines(
                dataLines,
                accumulatedText: &accumulatedText,
                completedResponse: &completedResponse,
                continuation: continuation,
                metadata: metadata
              )
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }

          try Self.processStreamDataLines(
            dataLines,
            accumulatedText: &accumulatedText,
            completedResponse: &completedResponse,
            continuation: continuation,
            metadata: metadata
          )
          continuation.yield(
            .completed(
              completedResponse ?? LLMResponse(
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

  func responsesHTTPRequest(
    for request: LLMRequest,
    stream: Bool
  ) throws -> OpenAIHTTPRequest {
    let url = baseURL.appendingPathComponent("responses")
    let body = OpenAIResponsesRequest(
      model: model,
      input: request.openAIInputMessages,
      instructions: request.openAIInstructions,
      maxOutputTokens: request.parameters.maxOutputTokens,
      temperature: request.parameters.temperature,
      topP: request.parameters.topP,
      stop: request.parameters.stopSequences.isEmpty ? nil : request.parameters.stopSequences,
      text: request.responseFormat.openAIText,
      tools: request.tools.isEmpty ? nil : request.tools.map(OpenAITool.init),
      toolChoice: request.toolChoice.map(OpenAIToolChoice.init),
      stream: stream
    )
    let data = try JSONEncoder.provider.encode(body)
    var headers = [
      "Authorization": "Bearer \(apiKey)",
      "Content-Type": "application/json",
    ]
    if let organizationID {
      headers["OpenAI-Organization"] = organizationID
    }
    if let projectID {
      headers["OpenAI-Project"] = projectID
    }
    return OpenAIHTTPRequest(url: url, headers: headers, body: data)
  }

  private func metadata(for request: LLMRequest) -> LLMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  private static func validate(_ response: OpenAIHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      let providerMessage = (try? JSONDecoder.provider.decode(OpenAIErrorPayload.self, from: response.body))
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
      return .provider(providerMessage ?? "OpenAI request failed with HTTP \(statusCode).")
    }
  }

  private static func processStreamDataLines(
    _ dataLines: [String],
    accumulatedText: inout String,
    completedResponse: inout LLMResponse?,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation,
    metadata: LLMProviderMetadata
  ) throws {
    for dataLine in dataLines where dataLine != "[DONE]" && !dataLine.isEmpty {
      let data = Data(dataLine.utf8)
      let event = try JSONDecoder.provider.decode(OpenAIStreamEvent.self, from: data)
      switch event.type {
      case "response.output_text.delta":
        if let delta = event.delta {
          accumulatedText += delta
          continuation.yield(.textDelta(delta))
        }
      case "response.output_item.done":
        if let toolCall = event.item?.toolCall {
          continuation.yield(.toolCall(toolCall))
        }
      case "response.completed", "response.done":
        if let response = event.response?.llmResponse(metadata: metadata) {
          completedResponse = response
        }
      default:
        break
      }
    }
  }
}

extension AnyLLMClient {
  public static func openAI(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil
  ) -> Self {
    Self(
      OpenAIClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        organizationID: organizationID,
        projectID: projectID
      )
    )
  }
}

private struct OpenAIResponsesRequest: Encodable {
  var model: String
  var input: [OpenAIInputMessage]
  var instructions: String?
  var maxOutputTokens: Int?
  var temperature: Double?
  var topP: Double?
  var stop: [String]?
  var text: OpenAITextConfig?
  var tools: [OpenAITool]?
  var toolChoice: OpenAIToolChoice?
  var stream: Bool

  enum CodingKeys: String, CodingKey {
    case input
    case instructions
    case maxOutputTokens = "max_output_tokens"
    case model
    case stop
    case stream
    case temperature
    case text
    case toolChoice = "tool_choice"
    case tools
    case topP = "top_p"
  }
}

private struct OpenAIInputMessage: Encodable {
  var role: String
  var content: String
}

private struct OpenAITextConfig: Encodable {
  var format: OpenAITextFormat
}

private enum OpenAITextFormat: Encodable {
  case jsonObject
  case jsonSchema(LLMJSONSchema)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .jsonObject:
      try container.encode("json_object", forKey: .type)
    case let .jsonSchema(schema):
      try container.encode("json_schema", forKey: .type)
      try container.encode(schema.name, forKey: .name)
      try container.encodeIfPresent(schema.description, forKey: .description)
      try container.encode(schema.schema, forKey: .schema)
      try container.encode(schema.strict, forKey: .strict)
    }
  }

  enum CodingKeys: String, CodingKey {
    case description
    case name
    case schema
    case strict
    case type
  }
}

private struct OpenAITool: Encodable {
  var name: String
  var description: String
  var parameters: JSONValue
  var strict: Bool
  var type = "function"

  init(_ definition: LLMToolDefinition) {
    self.description = definition.description
    self.name = definition.name
    self.parameters = definition.inputSchema
    self.strict = definition.strict
  }
}

private enum OpenAIToolChoice: Encodable {
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
    switch self {
    case .auto:
      var container = encoder.singleValueContainer()
      try container.encode("auto")
    case .none:
      var container = encoder.singleValueContainer()
      try container.encode("none")
    case .required:
      var container = encoder.singleValueContainer()
      try container.encode("required")
    case let .tool(name):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("function", forKey: .type)
      try container.encode(name, forKey: .name)
    }
  }

  enum CodingKeys: String, CodingKey {
    case name
    case type
  }
}

private struct OpenAIResponsePayload: Decodable {
  var finishReason: String?
  var id: String?
  var model: String?
  var output: [OpenAIOutputItem]?
  var outputText: String?
  var status: String?
  var usage: OpenAIUsage?

  enum CodingKeys: String, CodingKey {
    case finishReason = "finish_reason"
    case id
    case model
    case output
    case outputText = "output_text"
    case status
    case usage
  }

  func llmResponse(metadata: LLMProviderMetadata) -> LLMResponse {
    let toolCalls = output?.compactMap(\.toolCall) ?? []
    let text = outputText ?? output?.flatMap(\.textParts).joined() ?? ""
    return LLMResponse(
      id: id ?? UUID().uuidString,
      text: text,
      toolCalls: toolCalls,
      finishReason: mappedFinishReason,
      tokenUsage: usage?.tokenUsage,
      model: model ?? metadata.modelIdentifier,
      metadata: metadata
    )
  }

  private var mappedFinishReason: LLMFinishReason? {
    switch finishReason ?? status {
    case "completed":
      return .stop
    case "incomplete", "length":
      return .length
    case "content_filter":
      return .contentFilter
    case "tool_calls":
      return .toolCalls
    case nil:
      return nil
    default:
      return .unknown
    }
  }
}

private struct OpenAIOutputItem: Decodable {
  var arguments: String?
  var callID: String?
  var content: [OpenAIOutputContent]?
  var id: String?
  var name: String?
  var type: String?

  enum CodingKeys: String, CodingKey {
    case arguments
    case callID = "call_id"
    case content
    case id
    case name
    case type
  }

  var textParts: [String] {
    content?.compactMap(\.text) ?? []
  }

  var toolCall: LLMToolCall? {
    guard type == "function_call",
          let name,
          let arguments
    else { return nil }
    return LLMToolCall(
      id: callID ?? id ?? UUID().uuidString,
      name: name,
      argumentsJSON: arguments
    )
  }
}

private struct OpenAIOutputContent: Decodable {
  var text: String?
  var type: String?
}

private struct OpenAIUsage: Decodable {
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

private struct OpenAIStreamEvent: Decodable {
  var delta: String?
  var item: OpenAIOutputItem?
  var response: OpenAIResponsePayload?
  var type: String?
}

private struct OpenAIErrorPayload: Decodable {
  var error: OpenAIProviderError
}

private struct OpenAIProviderError: Decodable {
  var message: String?
}

private extension Array where Element == LLMMessage {
  var openAIInputMessages: [OpenAIInputMessage] {
    filter { $0.role != .system && $0.role != .developer }
      .map { message in
        OpenAIInputMessage(
          role: message.role.openAIRole,
          content: message.openAIContent
        )
      }
  }
}

private extension LLMMessage {
  var openAIContent: String {
    switch role {
    case .tool:
      return "Tool result\(toolCallID.map { " \($0)" } ?? ""):\n\(content)"
    case .assistant, .developer, .system, .user:
      return content
    }
  }
}

private extension LLMMessageRole {
  var openAIRole: String {
    switch self {
    case .assistant:
      return "assistant"
    case .developer:
      return "developer"
    case .system:
      return "system"
    case .tool:
      return "user"
    case .user:
      return "user"
    }
  }
}

private extension LLMRequest {
  var openAIInputMessages: [OpenAIInputMessage] {
    let messages = messages.openAIInputMessages
    return messages.isEmpty ? [OpenAIInputMessage(role: "user", content: "")] : messages
  }

  var openAIInstructions: String? {
    let messageInstructions = messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    let instructions = [instructions, messageInstructions]
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: "\n\n")
    return instructions.isEmpty ? nil : instructions
  }
}

private extension LLMResponseFormat {
  var openAIText: OpenAITextConfig? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return OpenAITextConfig(format: .jsonObject)
    case let .jsonSchema(schema):
      return OpenAITextConfig(format: .jsonSchema(schema))
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

private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
  response.allHeaderFields.reduce(into: [:]) { headers, field in
    if let key = field.key as? String,
       let value = field.value as? String
    {
      headers[key] = value
    }
  }
}
