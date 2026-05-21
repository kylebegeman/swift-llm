# Provider Adapters

## Purpose

SwiftLLM now has one client surface for multiple model backends:

- Apple Foundation Models through `SwiftLLMFoundationModels`
- OpenAI through `SwiftLLMOpenAI`
- Anthropic through `SwiftLLMAnthropic`
- deterministic local/test clients through `SwiftLLM`

The intent is not to pretend every provider has the same capabilities. The intent is to make common app workflows ergonomic while preserving provider-specific behavior at the adapter boundary.

## Core Types

Provider-neutral usage starts with `LLMClient`:

```swift
public protocol LLMClient: Sendable {
  var metadata: LLMProviderMetadata { get }

  func respond(to request: LLMRequest) async throws -> LLMResponse
  func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>
}
```

The core request model includes:

- `LLMMessage`
- `LLMGenerationParameters`
- `LLMResponseFormat`
- `LLMJSONSchema`
- `LLMToolDefinition`
- `LLMToolChoice`
- `LLMRequest`
- `LLMResponse`
- `LLMToolCall`
- `LLMClientError`

This keeps app code focused on the thing it is asking the model to do, not the transport shape for a particular provider.

## Provider Targets

### Foundation Models

`FoundationModelClient` now conforms to `LLMClient`.

The common `respond(to:)` API compiles an `LLMRequest` into the existing Foundation Models request type. Typed guided generation remains available through the Foundation-specific API when Apple's `FoundationModels` framework can be imported.

This is still the preferred default for offline Apple app flows.

### OpenAI

`OpenAIClient` translates `LLMRequest` into the OpenAI Responses API:

- `instructions` and system/developer messages become Responses `instructions`
- user/assistant messages become Responses `input`
- `.jsonObject` and `.jsonSchema` become `text.format`
- tools become function tools
- tool choices are encoded as `auto`, `none`, `required`, or named function choice
- response parsing reads `output_text`, message content, function calls, finish status, and token usage

The adapter follows the public OpenAI Responses and Structured Outputs documentation:

- https://platform.openai.com/docs/api-reference/responses
- https://platform.openai.com/docs/guides/structured-outputs

### Anthropic

`AnthropicClient` translates `LLMRequest` into the Anthropic Messages API:

- `instructions` and system/developer messages become the Anthropic `system` field
- user/assistant messages become Anthropic `messages`
- response format constraints are appended to system instructions
- tools become Anthropic tool definitions
- tool choices map to `auto`, `none`, `any`, or a named tool
- response parsing reads text blocks, tool use blocks, stop reasons, and token usage

The adapter follows Anthropic's Messages API documentation:

- https://docs.anthropic.com/en/api/messages
- https://docs.anthropic.com/en/api/messages-examples

## Routing

`LLMRouter` lets an app express a fallback ladder:

```swift
let client = LLMRouter(
  primary: AnyLLMClient(FoundationModelClient.live),
  fallbacks: [
    .openAI(apiKey: openAIKey, model: "your-openai-model"),
    .anthropic(apiKey: anthropicKey, model: "your-anthropic-model"),
  ]
)
```

The first implementation retries `respond(to:)` across providers. Streaming currently delegates to the primary provider because mid-stream fallback has tricky UX and state semantics.

## Prompt/RAG Pipeline

`LLMPipeline` combines:

- a provider-neutral client
- a prompt contract
- optional few-shot examples
- optional local retrieval
- optional tools and response formats

This is the high-level ergonomic API for app features that should feel the same whether they run locally or against a configured provider.

## Credential Policy

SwiftLLM accepts API keys at initialization time and does not store them.

Apps own:

- Keychain storage
- developer settings
- environment variable loading
- test fixture keys
- enterprise proxy policy
- user-facing disclosure and consent

That keeps SwiftLLM useful for private projects without baking in a public-library security stance too early.

## Testing Policy

Provider adapters use injectable HTTP transports. Tests should verify:

- request shape
- required headers
- response parsing
- error normalization
- tool-call conversion
- token usage conversion

Tests should not call real provider APIs by default.
