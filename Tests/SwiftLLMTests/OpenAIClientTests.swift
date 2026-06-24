import Foundation
import SwiftLLM
import SwiftLLMOpenAI
import Testing

@Suite("OpenAI client")
struct OpenAIClientTests {
  // MARK: - OpenAI

  @Test
  func openAIClientEncodesResponsesRequestAndParsesResponse() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      organizationID: "org-test",
      projectID: "proj-test",
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_1",
              "model": "gpt-test",
              "status": "completed",
              "output_text": "Hello from OpenAI.",
              "output": [
                {
                  "type": "function_call",
                  "call_id": "call_1",
                  "name": "lookup_note",
                  "arguments": "{\\"id\\":\\"1\\"}"
                }
              ],
              "usage": {
                "input_tokens": 12,
                "output_tokens": 4
              }
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LLMRequest(
        instructions: "Be concise.",
        messages: [
          .system("Keep private context private."),
          .user("Summarize this note."),
        ],
        responseFormat: .jsonSchema(
          LLMJSONSchema(
            name: "summary",
            schema: [
              "type": "object",
              "properties": [
                "summary": [
                  "type": "string",
                ],
              ],
              "required": ["summary"],
              "additionalProperties": false,
            ]
          )
        ),
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
        toolChoice: .tool("lookup_note"),
        parameters: LLMGenerationParameters(
          temperature: 0.2,
          maxOutputTokens: 120,
          topP: 0.9,
          stopSequences: ["END"]
        ),
        metadata: [
          "promptVersion": "summary-v3",
        ]
      )
    )
    let request = try #require(await capture.value())
    let body = try request.jsonObject()

    #expect(request.url.absoluteString == "https://example.test/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["OpenAI-Organization"] == "org-test")
    #expect(request.headers["OpenAI-Project"] == "proj-test")
    #expect(body["model"] == "gpt-test")
    #expect(body["max_output_tokens"] == 120)
    #expect(body["instructions"]?.stringValue?.contains("Be concise.") == true)
    #expect(body["instructions"]?.stringValue?.contains("Keep private context private.") == true)
    #expect(body["input"]?.arrayValue?.first?.objectValue?["role"] == "user")
    #expect(body["text"]?.objectValue?["format"]?.objectValue?["type"] == "json_schema")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["name"] == "lookup_note")
    #expect(body["tool_choice"]?.objectValue?["name"] == "lookup_note")
    #expect(response.text == "Hello from OpenAI.")
    #expect(response.toolCalls.first?.name == "lookup_note")
    #expect(response.message.toolCalls.first?.id == "call_1")
    #expect(response.tokenUsage?.measuredInputTokens == 12)
    #expect(response.metadata.providerKind == .openAI)
    #expect(response.metadata.promptVersion == "summary-v3")
  }

  @Test
  func openAIClientStreamsThroughInjectedTransport() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return OpenAIHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { request in
          await capture.record(request)
          return OpenAIHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"response.output_text.delta","delta":"Hello "}"#,
              "",
              #"data: {"type":"response.output_text.delta","delta":"stream"}"#,
              "",
              #"data: {"type":"response.completed","response":{"id":"resp_stream","status":"completed","output_text":"Hello stream","usage":{"input_tokens":3,"output_tokens":2}}}"#,
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
        metadata: ["promptVersion": "stream-v1"]
      )
    ) {
      events.append(event)
    }
    let request = try #require(await capture.value())

    #expect(request.url.absoluteString == "https://example.test/v1/responses")
    #expect(try request.jsonObject()["stream"] == true)
    #expect(events.textDeltas == ["Hello ", "stream"])
    #expect(events.completedResponse?.text == "Hello stream")
    #expect(events.completedResponse?.metadata.promptVersion == "stream-v1")
    #expect(events.completedResponse?.tokenUsage?.measuredOutputTokens == 2)
  }

  @Test
  func openAIClientThrowsFailedResponsePayloads() async throws {
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport { _ in
        OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_failed",
              "model": "gpt-test",
              "status": "failed",
              "error": {
                "code": "server_error",
                "message": "The model failed to generate a response."
              }
            }
            """.utf8
          )
        )
      }
    )

    do {
      _ = try await client.respond(to: LLMRequest(messages: [.user("Fail.")]))
      Issue.record("Expected failed OpenAI response payload to throw.")
    } catch let error as LLMClientError {
      #expect(error.reason == .provider("The model failed to generate a response."))
    }
  }

  @Test
  func openAIClientThrowsStreamErrorEvents() async throws {
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport(
        send: { _ in OpenAIHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          OpenAIHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"response.failed","response":{"id":"resp_failed","status":"failed","error":{"code":"server_error","message":"Stream failed."}}}"#,
              "",
            ])
          )
        }
      )
    )

    do {
      for try await _ in client.stream(to: LLMRequest(messages: [.user("Stream.")])) {}
      Issue.record("Expected OpenAI stream failure event to throw.")
    } catch let error as LLMClientError {
      #expect(error.reason == .provider("Stream failed."))
    }
  }

  @Test
  func openAIClientEncodesNativeToolHistory() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_tool",
              "model": "gpt-test",
              "status": "completed",
              "output_text": "Tool result accepted."
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
                id: "call_1",
                name: "lookup_note",
                argumentsJSON: #"{"id":"1"}"#
              ),
            ]
          ),
          .tool(#"{"title":"Private note"}"#, toolCallID: "call_1"),
        ]
      )
    )

    let body = try #require(await capture.value()).jsonObject()
    let input = try #require(body["input"]?.arrayValue)

    #expect(input[0].objectValue?["role"] == "user")
    #expect(input[1].objectValue?["type"] == "function_call")
    #expect(input[1].objectValue?["call_id"] == "call_1")
    #expect(input[1].objectValue?["arguments"] == #"{"id":"1"}"#)
    #expect(input[2].objectValue?["type"] == "function_call_output")
    #expect(input[2].objectValue?["call_id"] == "call_1")
    #expect(input[2].objectValue?["output"] == #"{"title":"Private note"}"#)
  }
}
