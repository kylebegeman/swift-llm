import Foundation
import SwiftLLM

extension OpenAIClient {
  func responsesHTTPRequest(
    for request: LLMRequest,
    stream: Bool
  ) throws -> OpenAIHTTPRequest {
    let url = baseURL.appendingPathComponent("responses")
    let body = OpenAIResponsesRequest(
      model: model,
      input: try request.openAIInputItems(),
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
}

// MARK: - Request Encoding

private struct OpenAIResponsesRequest: Encodable {
  var model: String
  var input: [OpenAIInputItem]
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

private enum OpenAIInputItem: Encodable {
  case functionCall(OpenAIFunctionCallInput)
  case functionCallOutput(OpenAIFunctionCallOutputInput)
  case message(OpenAIInputMessage)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case let .functionCall(value):
      try value.encode(to: encoder)
    case let .functionCallOutput(value):
      try value.encode(to: encoder)
    case let .message(value):
      try value.encode(to: encoder)
    }
  }
}

private struct OpenAIFunctionCallInput: Encodable {
  var arguments: String
  var callID: String
  var id: String
  var name: String
  var type = "function_call"

  init(_ toolCall: LLMToolCall) {
    self.arguments = toolCall.argumentsJSON
    self.callID = toolCall.id
    self.id = toolCall.id
    self.name = toolCall.name
  }

  enum CodingKeys: String, CodingKey {
    case arguments
    case callID = "call_id"
    case id
    case name
    case type
  }
}

private struct OpenAIFunctionCallOutputInput: Encodable {
  var callID: String
  var output: String
  var type = "function_call_output"

  init(message: LLMMessage) throws {
    guard let toolCallID = message.toolCallID,
          !toolCallID.isEmpty
    else {
      throw LLMClientError(
        reason: .badRequest,
        debugDescription: "OpenAI tool result messages require a non-empty toolCallID."
      )
    }
    self.callID = toolCallID
    self.output = message.content
  }

  enum CodingKeys: String, CodingKey {
    case callID = "call_id"
    case output
    case type
  }
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

// MARK: - Request Mapping

private extension LLMRequest {
  func openAIInputItems() throws -> [OpenAIInputItem] {
    let inputItems = try messages
      .filter { $0.role != .system && $0.role != .developer }
      .flatMap { message in
        try message.openAIInputItems
      }
    return inputItems.isEmpty ? [.message(OpenAIInputMessage(role: "user", content: ""))] : inputItems
  }
}

private extension LLMMessage {
  var openAIInputItems: [OpenAIInputItem] {
    get throws {
      switch role {
      case .assistant:
        var inputItems: [OpenAIInputItem] = []
        if !content.isEmpty {
          inputItems.append(.message(OpenAIInputMessage(role: role.openAIRole, content: content)))
        }
        inputItems.append(contentsOf: toolCalls.map { .functionCall(OpenAIFunctionCallInput($0)) })
        return inputItems
      case .tool:
        return [.functionCallOutput(try OpenAIFunctionCallOutputInput(message: self))]
      case .developer, .system, .user:
        return [.message(OpenAIInputMessage(role: role.openAIRole, content: content))]
      }
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
