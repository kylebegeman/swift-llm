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
        )
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
    #expect(response.tokenUsage?.measuredInputTokens == 12)
    #expect(response.metadata.providerKind == .openAI)
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
        parameters: LLMGenerationParameters(maxOutputTokens: 80)
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
    #expect(response.tokenUsage?.measuredOutputTokens == 5)
    #expect(response.metadata.providerKind == .anthropic)
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
        parameters: LLMGenerationParameters(maxOutputTokens: 48)
      )
    )

    #expect(response.text == "Foundation response for a private transcript")
    #expect(response.metadata.providerKind == .appleFoundationModels)
    #expect(response.tokenUsage?.estimatedOutputTokens == 5)
  }
}

private actor RequestCapture<Request: Sendable> {
  private var request: Request?

  func record(_ request: Request) {
    self.request = request
  }

  func value() -> Request? {
    request
  }
}

private extension OpenAIHTTPRequest {
  func jsonObject() throws -> [String: JSONValue] {
    try JSONDecoder().decode(JSONValue.self, from: body).objectValue ?? [:]
  }
}

private extension AnthropicHTTPRequest {
  func jsonObject() throws -> [String: JSONValue] {
    try JSONDecoder().decode(JSONValue.self, from: body).objectValue ?? [:]
  }
}

private extension JSONValue {
  var arrayValue: [JSONValue]? {
    guard case let .array(value) = self else { return nil }
    return value
  }

  var objectValue: [String: JSONValue]? {
    guard case let .object(value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case let .string(value) = self else { return nil }
    return value
  }
}
