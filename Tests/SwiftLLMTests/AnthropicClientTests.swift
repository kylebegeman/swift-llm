import Foundation
import SwiftLLM
import SwiftLLMAnthropic
import Testing

@Suite("Anthropic client")
struct AnthropicClientTests {
  // MARK: - Anthropic

  @Test
  func anthropicClientEncodesMessagesRequestAndParsesResponse() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "anthropic-test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      defaultMaxTokens: 512,
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "msg_1",
              "type": "message",
              "role": "assistant",
              "model": "claude-test",
              "content": [
                {
                  "type": "text",
                  "text": "Hello from Claude."
                },
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "lookup_note",
                  "input": {
                    "id": "1"
                  }
                }
              ],
              "stop_reason": "tool_use",
              "usage": {
                "input_tokens": 10,
                "output_tokens": 5
              }
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LLMRequest(
        instructions: "Answer with citations.",
        messages: [
          .developer("Prefer compact output."),
          .user("Summarize this note."),
        ],
        tools: [
          LLMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: [
              "type": "object",
              "properties": [
                "id": [
                  "type": "string",
                ],
              ],
            ]
          ),
        ],
        toolChoice: .required,
        parameters: LLMGenerationParameters(maxOutputTokens: 80),
        metadata: [
          "promptVersion": "summary-v4",
        ]
      )
    )
    let request = try #require(await capture.value())
    let body = try request.jsonObject()

    #expect(request.url.absoluteString == "https://example.test/v1/messages")
    #expect(request.headers["x-api-key"] == "anthropic-test-key")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    #expect(body["model"] == "claude-test")
    #expect(body["max_tokens"] == 80)
    #expect(body["system"]?.stringValue?.contains("Answer with citations.") == true)
    #expect(body["system"]?.stringValue?.contains("Prefer compact output.") == true)
    #expect(body["messages"]?.arrayValue?.first?.objectValue?["role"] == "user")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["input_schema"]?.objectValue?["type"] == "object")
    #expect(body["tool_choice"]?.objectValue?["type"] == "any")
    #expect(response.text == "Hello from Claude.")
    #expect(response.toolCalls.first?.name == "lookup_note")
    #expect(response.message.toolCalls.first?.id == "toolu_1")
    #expect(response.tokenUsage?.measuredOutputTokens == 5)
    #expect(response.metadata.providerKind == .anthropic)
    #expect(response.metadata.promptVersion == "summary-v4")
  }

  @Test
  func anthropicClientStreamsThroughInjectedTransport() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return AnthropicHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { request in
          await capture.record(request)
          return AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello "}}"#,
              "",
              #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"stream"}}"#,
              "",
              #"data: {"type":"message_stop"}"#,
              "",
            ])
          )
        }
      )
    )

    var events: [LLMStreamEvent] = []
    for try await event in client.stream(
      to: LLMRequest(
        messages: [.user("Stream this.")],
        metadata: ["promptVersion": "stream-v2"]
      )
    ) {
      events.append(event)
    }
    let request = try #require(await capture.value())

    #expect(request.url.absoluteString == "https://example.test/v1/messages")
    #expect(try request.jsonObject()["stream"] == true)
    #expect(events.textDeltas == ["Hello ", "stream"])
    #expect(events.completedResponse?.text == "Hello stream")
    #expect(events.completedResponse?.metadata.promptVersion == "stream-v2")
  }

  @Test
  func anthropicClientStreamsToolCallsThroughInjectedTransport() async throws {
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return AnthropicHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { _ in
          AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"message_start","message":{"usage":{"input_tokens":8,"output_tokens":1}}}"#,
              "",
              #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_stream","name":"lookup_note","input":{}}}"#,
              "",
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"id\":\""}}"#,
              "",
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"1\"}"}}"#,
              "",
              #"data: {"type":"content_block_stop","index":0}"#,
              "",
              #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}"#,
              "",
              #"data: {"type":"message_stop"}"#,
              "",
            ])
          )
        }
      )
    )

    var events: [LLMStreamEvent] = []
    for try await event in client.stream(
      to: LLMRequest(
        messages: [.user("Lookup note 1.")],
        tools: [
          LLMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: ["type": "object"]
          ),
        ]
      )
    ) {
      events.append(event)
    }

    #expect(events.toolCalls.map(\.id) == ["toolu_stream"])
    #expect(events.toolCalls.first?.name == "lookup_note")
    #expect(events.toolCalls.first?.argumentsJSON == #"{"id":"1"}"#)
    #expect(events.completedResponse?.finishReason == .toolCalls)
    #expect(events.completedResponse?.toolCalls.map(\.id) == ["toolu_stream"])
    #expect(events.completedResponse?.tokenUsage?.measuredInputTokens == 8)
    #expect(events.completedResponse?.tokenUsage?.measuredOutputTokens == 9)
  }

  @Test
  func anthropicClientThrowsStreamErrorEvents() async throws {
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport(
        send: { _ in AnthropicHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
              "",
            ])
          )
        }
      )
    )

    do {
      for try await _ in client.stream(to: LLMRequest(messages: [.user("Stream.")])) {}
      Issue.record("Expected Anthropic stream error event to throw.")
    } catch let error as LLMClientError {
      #expect(error.reason == .provider("Overloaded"))
    }
  }

  @Test
  func anthropicClientEncodesNativeToolHistory() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "msg_tool",
              "type": "message",
              "role": "assistant",
              "model": "claude-test",
              "content": [
                {
                  "type": "text",
                  "text": "Tool result accepted."
                }
              ],
              "stop_reason": "end_turn",
              "usage": {
                "input_tokens": 4,
                "output_tokens": 3
              }
            }
            """.utf8
          )
        )
      }
    )

    _ = try await client.respond(
      to: LLMRequest(
        messages: [
          .user("Look up note 1."),
          .assistant(
            "",
            toolCalls: [
              LLMToolCall(
                id: "toolu_1",
                name: "lookup_note",
                argumentsJSON: #"{"id":"1"}"#
              ),
            ]
          ),
          .tool("Not found", toolCallID: "toolu_1", isError: true),
          .user("Continue with what you know."),
        ]
      )
    )

    let body = try #require(await capture.value()).jsonObject()
    let messages = try #require(body["messages"]?.arrayValue)
    let assistantContent = try #require(messages[1].objectValue?["content"]?.arrayValue)
    let toolResultContent = try #require(messages[2].objectValue?["content"]?.arrayValue)

    #expect(messages[1].objectValue?["role"] == "assistant")
    #expect(assistantContent.first?.objectValue?["type"] == "tool_use")
    #expect(assistantContent.first?.objectValue?["id"] == "toolu_1")
    #expect(assistantContent.first?.objectValue?["input"]?.objectValue?["id"] == "1")
    #expect(messages[2].objectValue?["role"] == "user")
    #expect(toolResultContent[0].objectValue?["type"] == "tool_result")
    #expect(toolResultContent[0].objectValue?["tool_use_id"] == "toolu_1")
    #expect(toolResultContent[0].objectValue?["is_error"]?.boolValue == true)
    #expect(toolResultContent[1].objectValue?["text"] == "Continue with what you know.")
  }
}
