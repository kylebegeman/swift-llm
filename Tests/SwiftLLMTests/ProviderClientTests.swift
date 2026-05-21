import Foundation
import SwiftLLM
import SwiftLLMAnthropic
import SwiftLLMFoundationModels
import SwiftLLMOpenAI
import Testing

@Suite("Provider clients")
struct ProviderClientTests {
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

  @Test
  func routerFallsBackWhenPrimaryClientThrows() async throws {
    let failingMetadata = LLMProviderMetadata(
      modelIdentifier: "primary",
      privacyMode: .externalOptIn,
      promptVersion: "v1",
      providerDisplayName: "Primary",
      providerKind: .external
    )
    let primary = AnyLLMClient(metadata: failingMetadata) { _ in
      throw LLMClientError(reason: .unavailable)
    }
    let fallback = AnyLLMClient.testDouble { request in
      "Fallback handled \(request.messages.first?.content ?? "")"
    }
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    let response = try await router.respond(
      to: LLMRequest(messages: [.user("offline work")])
    )

    #expect(response.text == "Fallback handled offline work")
    #expect(response.metadata.providerKind == .testDouble)
  }

  @Test
  func routerDoesNotFallbackForBadRequestsByDefault() async throws {
    let fallback = AnyLLMClient.testDouble { _ in
      Issue.record("Fallback should not run for bad requests.")
      return "unexpected"
    }
    let router = LLMRouter(
      primary: AnyLLMClient(metadata: Self.metadata(name: "Primary")) { _ in
        throw LLMClientError(reason: .badRequest)
      },
      fallbacks: [fallback]
    )

    do {
      _ = try await router.respond(to: LLMRequest(messages: [.user("Bad request")]))
      Issue.record("Expected the router to preserve the bad request error.")
    } catch let error as LLMClientError {
      #expect(error.reason == .badRequest)
    }
  }

  @Test
  func routerUsesCapabilitiesToSkipIncompatibleProviders() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Local"),
      capabilities: LLMClientCapabilities(
        supportedFeatures: [.jsonObjectResponse, .jsonSchemaResponse, .streaming, .temperature]
      )
    ) { _ in
      Issue.record("Router should not call a provider that lacks required tool support.")
      return LLMResponse(text: "unexpected", metadata: Self.metadata(name: "Local"))
    }
    let router = LLMRouter(
      primary: primary,
      fallbacks: [
        .testDouble { _ in "Tool-capable fallback" },
      ]
    )

    let response = try await router.respond(
      to: LLMRequest(
        messages: [.user("Use a tool.")],
        tools: [
          LLMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: ["type": "object"]
          ),
        ],
        toolChoice: .required
      )
    )

    #expect(response.text == "Tool-capable fallback")
  }

  @Test
  func routerStreamsFromFallbackWhenPrimaryFailsBeforeOutput() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Primary"),
      respond: { _ in
        throw LLMClientError(reason: .unavailable)
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.started(Self.metadata(name: "Primary")))
          continuation.finish(throwing: LLMClientError(reason: .unavailable))
        }
      }
    )
    let fallback = AnyLLMClient(
      metadata: Self.metadata(name: "Fallback", providerKind: .testDouble),
      respond: { _ in
        LLMResponse(text: "Fallback stream", metadata: Self.metadata(name: "Fallback", providerKind: .testDouble))
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          let metadata = Self.metadata(name: "Fallback", providerKind: .testDouble)
          continuation.yield(.started(metadata))
          continuation.yield(.textDelta("Fallback stream"))
          continuation.yield(.completed(LLMResponse(text: "Fallback stream", metadata: metadata)))
          continuation.finish()
        }
      }
    )
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    var events: [LLMStreamEvent] = []
    for try await event in router.stream(to: LLMRequest(messages: [.user("Stream.")])) {
      events.append(event)
    }

    #expect(events.startedProviders == [.external, .testDouble])
    #expect(events.textDeltas == ["Fallback stream"])
    #expect(events.completedResponse?.metadata.providerKind == .testDouble)
  }

  @Test
  func routerDoesNotStreamFallbackAfterOutputStarts() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Primary"),
      respond: { _ in
        throw LLMClientError(reason: .unavailable)
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.started(Self.metadata(name: "Primary")))
          continuation.yield(.textDelta("partial"))
          continuation.finish(throwing: LLMClientError(reason: .unavailable))
        }
      }
    )
    let fallback = AnyLLMClient.testDouble { _ in
      Issue.record("Fallback should not run after output has started.")
      return "unexpected"
    }
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    var events: [LLMStreamEvent] = []
    do {
      for try await event in router.stream(to: LLMRequest(messages: [.user("Stream.")])) {
        events.append(event)
      }
      Issue.record("Expected stream to fail without fallback after output started.")
    } catch let error as LLMClientError {
      #expect(error.reason == .unavailable)
    }

    #expect(events.textDeltas == ["partial"])
  }

  @Test
  func pipelineInjectsLocalRetrievalContextBeforeGeneration() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "note",
          text: "Local retrieval should keep citations visible.",
          displayName: "Private note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 32
    )
    let pipeline = LLMPipeline(
      client: .testDouble { request in
        request.messages.first?.content ?? ""
      },
      ragPipeline: LocalRAGPipeline(
        retriever: retriever,
        packer: ContextPacker(
          budget: TokenBudget(
            contextLimit: 64,
            reservedResponseTokens: 8,
            safetyMarginTokens: 4
          )
        )
      )
    )

    let result = try await pipeline.run(
      task: LLMPromptTask(
        contract: PromptContract(
          id: "answer",
          version: "v2",
          instructions: "Answer from local context."
        ),
        retrievalQuery: { input in
          LocalRetrievalQuery(text: input, maxResults: 2)
        }
      ),
      input: "How should local retrieval handle citations?"
    )

    #expect(result.ragResult?.packedSnippets.count == 1)
    #expect(result.response.text.contains("Retrieved context:"))
    #expect(result.response.text.contains("Private note (note)"))
    #expect(result.request.metadata["promptID"] == "answer")
    #expect(result.compiledPrompt.metadata.promptVersion == "v2")
  }

  @Test
  func foundationModelClientCanRespondThroughCommonProtocol() async throws {
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        FoundationModelGenerationResponse(
          content: "Foundation response for \(request.prompt.userPrompt)",
          metadata: request.prompt.metadata,
          tokenUsage: LLMTokenUsage(
            estimatedInputTokens: 6,
            estimatedOutputTokens: 5
          ),
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2)
        )
      }
    )

    let response = try await client.respond(
      to: LLMRequest(
        instructions: "Summarize locally.",
        messages: [.user("a private transcript")],
        parameters: LLMGenerationParameters(maxOutputTokens: 48),
        metadata: [
          "promptVersion": "local-summary-v2",
        ]
      )
    )

    #expect(response.text == "Foundation response for a private transcript")
    #expect(response.metadata.providerKind == .appleFoundationModels)
    #expect(response.metadata.promptVersion == "local-summary-v2")
    #expect(response.tokenUsage?.estimatedOutputTokens == 5)
  }

  @Test
  func foundationModelClientRejectsUnsupportedProviderNeutralFeatures() async {
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        FoundationModelGenerationResponse(
          content: request.prompt.userPrompt,
          metadata: request.prompt.metadata,
          tokenUsage: LLMTokenUsage(
            estimatedInputTokens: 1,
            estimatedOutputTokens: 1
          ),
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2)
        )
      }
    )

    do {
      _ = try await client.respond(
        to: LLMRequest(
          messages: [.user("Use a tool.")],
          tools: [
            LLMToolDefinition(
              name: "lookup_note",
              description: "Look up a note.",
              inputSchema: [
                "type": "object",
              ]
            ),
          ]
        )
      )
      Issue.record("Expected FoundationModelClient to reject unsupported tool requests.")
    } catch let error as LLMClientError {
      #expect(error.reason == .unsupported)
    } catch {
      Issue.record("Expected LLMClientError, got \(error).")
    }
  }

  private static func metadata(
    name: String,
    providerKind: LLMProviderKind = .external
  ) -> LLMProviderMetadata {
    LLMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "test-v1",
      providerDisplayName: name,
      providerKind: providerKind
    )
  }
}
