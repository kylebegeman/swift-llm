import Foundation
import SwiftLLM
import SwiftLLMEvaluation
import SwiftLLMFoundationModels
import Testing

@Suite("Foundation Models support")
struct FoundationModelSupportTests {
  // MARK: - Foundation Models

  @Test
  func foundationModelAvailabilityMapsUnavailableStateToFallback() {
    let availability = FoundationModelAvailability.modelNotReady

    #expect(!availability.isAvailable)
    #expect(availability.fallbackReason == .unavailable)
    #expect(availability.diagnosticMessage == "The local language model is not ready.")
  }

  @Test
  func foundationModelFailureMapsContextErrorToFallback() {
    let failure = FoundationModelFailure(
      reason: .contextExceeded,
      debugDescription: "Prompt used too many tokens."
    )

    #expect(failure.fallbackReason == .contextExceeded)
    #expect(failure.errorDescription == "The request exceeded the Foundation Models context window.")
  }

  @Test
  func requestCapabilitiesReflectRequiredProviderFeatures() {
    let request = LLMRequest(
      messages: [
        .assistant(
          "",
          toolCalls: [
            LLMToolCall(id: "call_1", name: "lookup", argumentsJSON: "{}"),
          ]
        ),
        .tool("{}", toolCallID: "call_1"),
      ],
      responseFormat: .jsonSchema(
        LLMJSONSchema(name: "result", schema: ["type": "object"])
      ),
      tools: [
        LLMToolDefinition(
          name: "lookup",
          description: "Lookup data.",
          inputSchema: ["type": "object"]
        ),
      ],
      toolChoice: .required,
      parameters: LLMGenerationParameters(
        temperature: 0.2,
        topP: 0.9,
        stopSequences: ["END"]
      )
    )

    #expect(
      request.requiredCapabilities(streaming: true) == [
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

  @Test
  func providerCapabilityPresetsReflectInstructionSupport() {
    #expect(LLMClientCapabilities.deterministicLocal.supports(.instructions))
    #expect(LLMClientCapabilities.openAIResponses.supports(.instructions))
    #expect(LLMClientCapabilities.anthropicMessages.supports(.instructions))
    #expect(LLMClientCapabilities.foundationModelsProviderNeutral.supports(.instructions))
    #expect(!LLMClientCapabilities.foundationModelsProviderNeutral.supports(.tools))
    #expect(!LLMClientCapabilities.foundationModelsProviderNeutral.supports(.toolResults))
  }

  @Test
  func llmMessageDecodingDefaultsToolFieldsForPersistedMessages() throws {
    let data = Data(
      """
      {
        "role": "assistant",
        "content": "Older persisted response."
      }
      """.utf8
    )

    let message = try JSONDecoder().decode(LLMMessage.self, from: data)

    #expect(message.role == .assistant)
    #expect(message.content == "Older persisted response.")
    #expect(message.toolCalls.isEmpty)
    #expect(message.toolCallID == nil)
    #expect(message.toolResultIsError == false)
  }

  @Test
  func foundationModelFakeClientCanExerciseGenerationWithoutFramework() async throws {
    let metadata = FoundationModelDefaults.metadata(promptVersion: "test-v1")
    let contract = PromptContract(
      id: "summary",
      version: "v1",
      instructions: "Summarize in one sentence."
    )
    let prompt = CompiledPrompt(
      contract: contract,
      metadata: metadata,
      userPrompt: "Summarize this local transcript."
    )
    let startedAt = Date(timeIntervalSince1970: 10)
    let completedAt = Date(timeIntervalSince1970: 11)
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        FoundationModelGenerationResponse(
          content: "This is a local summary.",
          metadata: request.prompt.metadata,
          tokenUsage: LLMTokenUsage(
            estimatedInputTokens: 8,
            estimatedOutputTokens: 6
          ),
          startedAt: startedAt,
          completedAt: completedAt
        )
      }
    )

    let response = try await client.respond(
      FoundationModelGenerationRequest(
        prompt: prompt,
        options: FoundationModelGenerationOptions(maximumResponseTokens: 64)
      )
    )

    #expect(response.content == "This is a local summary.")
    #expect(response.metadata.promptVersion == "test-v1")
    #expect(response.tokenUsage.estimatedInputTokens == 8)
    #expect(response.candidate.output == "This is a local summary.")
  }

  @Test
  func unavailableFoundationModelClientFallsBackToHeuristicTokenCounting() async throws {
    let count = try await FoundationModelClient.unavailable.countTokens(
      FoundationModelTokenCountRequest(text: "A short local prompt")
    )

    #expect(count == TokenCounter.latinHeuristic.count("A short local prompt"))
    #expect(FoundationModelClient.unavailable.availability() == .unavailableInBuild)
  }
}
