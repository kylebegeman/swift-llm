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
  var capabilities: LLMClientCapabilities { get }
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
- `LLMClientCapabilities`

This keeps app code focused on the thing it is asking the model to do, not the transport shape for a particular provider.

Capability negotiation is intentionally explicit. Adapters publish support for tools, tool results, response formats, sampling options, stop sequences, native JSON schema support, streaming, and context windows where known. `LLMRouter` uses those capabilities before dispatch so a request that requires tools can skip a local adapter that cannot honor them.

## Provider Targets

### Foundation Models

`FoundationModelClient` now conforms to `LLMClient`.

The common `respond(to:)` API compiles an `LLMRequest` into the existing Foundation Models request type. Typed guided generation remains available through the Foundation-specific API when Apple's `FoundationModels` framework can be imported.

Native Foundation Models tool execution is available through the typed Foundation-specific API by passing `[any Tool]` to `FoundationModelClient.respond(to:tools:)`, `respond(generating:request:tools:)`, or `prewarm(_:tools:)`. The small `FoundationModelToolConfiguration` wrapper preserves tool names and approximate definition-token cost for diagnostics without moving Apple framework types into the core target.

The provider-neutral Foundation adapter rejects features it cannot honor generically, including tool calls, top-p sampling, and stop sequences. That keeps a request from silently producing different behavior locally than it would with a cloud provider.

This is still the preferred default for offline Apple app flows.

### OpenAI

`OpenAIClient` translates `LLMRequest` into the OpenAI Responses API:

- `instructions` and system/developer messages become Responses `instructions`
- user/assistant messages become Responses `input`
- `.jsonObject` and `.jsonSchema` become `text.format`
- tools become function tools
- tool choices are encoded as `auto`, `none`, `required`, or named function choice
- assistant tool calls and tool-result messages become native `function_call` and `function_call_output` input items
- response parsing reads `output_text`, message content, function calls, finish status, and token usage
- failed response payloads and streaming failure events are normalized into `LLMClientError`
- response and streaming transports are injectable

The adapter follows the public OpenAI Responses and Structured Outputs documentation:

- https://platform.openai.com/docs/api-reference/responses
- https://platform.openai.com/docs/guides/structured-outputs
- https://platform.openai.com/docs/guides/streaming-responses

### Anthropic

`AnthropicClient` translates `LLMRequest` into the Anthropic Messages API:

- `instructions` and system/developer messages become the Anthropic `system` field
- user/assistant messages become Anthropic `messages`
- response format constraints are appended to system instructions
- tools become Anthropic tool definitions
- tool choices map to `auto`, `none`, `any`, or a named tool
- assistant tool calls and tool-result messages become native `tool_use` and `tool_result` content blocks
- response parsing reads text blocks, tool use blocks, stop reasons, and token usage
- streaming parsing handles text deltas, tool-use JSON deltas, stop reasons, token usage, and provider error events
- response and streaming transports are injectable

The adapter follows Anthropic's Messages API documentation:

- https://docs.anthropic.com/en/api/messages
- https://docs.anthropic.com/en/api/messages-examples
- https://docs.anthropic.com/en/docs/build-with-claude/streaming

## Routing And Fallback

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

Routing is capability-aware. Before calling a provider, the router checks whether the request requires unsupported features such as tool calling, tool results, top-p sampling, stop sequences, JSON response formats, or streaming.

The default fallback policy retries only failures that are reasonable to recover from by trying another provider:

- unavailable providers
- rate limits
- exceeded context windows
- unsupported capabilities
- unsupported local model guides or locales
- unavailable local model assets
- concurrent local model requests

The default policy does not retry bad requests, authentication failures, guardrail/refusal failures, decoding bugs, validation failures, cancellations, or unknown provider errors. Apps can opt into `.always`, `.never`, or a custom `LLMRouterFallbackPolicy`.

Streaming uses `LLMStreamFallbackMode.beforeFirstOutput` by default. If a provider fails before yielding text, tool calls, or a completion event, the router can continue with a fallback provider. Once output starts, the stream fails rather than silently splicing two providers into one partial response.

## Prompt/RAG Pipeline

`LLMPipeline` combines:

- a provider-neutral client
- a prompt contract
- optional few-shot examples
- optional local retrieval
- optional tools and response formats

This is the high-level ergonomic API for app features that should feel the same whether they run locally or against a configured provider.

## Credential Policy

SwiftLLM accepts API keys at initialization time and does not persist them or define a credential storage policy.

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
- streaming event parsing
- error normalization
- tool-call conversion
- native tool-result conversion
- capability-based routing behavior
- token usage conversion

Tests should not call real provider APIs by default.
