# Foundation Models Wrapper

## Use When

Use this card for availability, locale support, guided generation, tool calling, token counts, safety, guardrails, or performance work.

## Quick Facts

- Apple Foundation Models are available on iOS/iPadOS/macOS/Mac Catalyst/visionOS 26-era platforms.
- The system model must be checked for availability before use.
- The model context window is small enough that token budgeting is mandatory.
- Guided generation schemas consume context.
- Tool definitions and tool outputs consume context.
- Model behavior can change with OS updates.

## Current Package Shape

`SwiftLLMFoundationModels` currently owns:

- `FoundationModelAvailability`
- `FoundationModelClient`
- `FoundationModelDefaults`
- `FoundationModelGenerationOptions`
- `FoundationModelGenerationRequest`
- `FoundationModelGenerationResponse`
- `FoundationModelExecutionTarget`
- `FoundationModelRuntimeProfile`
- `FoundationModelQuotaStatus`
- `FoundationModelReasoningEffort`
- `FoundationModelToolConfiguration` when `FoundationModels` is importable
- `FoundationModelFailure`
- `FoundationModelErrorNormalizer`
- core `LLMContextPlan` metadata for instructions, prompt payloads, guided generation schemas,
  transcript rehydration, prewarm prefixes, and tool definitions

It is now the typed adapter layer for availability, token counting, prewarming, text generation,
guided generation and native tool calls where `FoundationModels` is importable, context-plan
budgeting, error normalization, response metadata, and pre-SDK readiness models for Private Cloud
Compute, provider packages, reasoning, quota, and dynamic context size. Richer stream feedback
capture is still future work.

## Source Of Truth

- Durable package docs: `../../docs/02-foundation-models-reference.md`
- Current code: `Sources/SwiftLLMFoundationModels/`

## Common Failure Modes

- Assuming the model is available.
- Reusing one session for long tasks until context overflows.
- Putting untrusted user text into instructions.
- Creating schemas or tools that are too verbose.
- Retrying the same failed prompt without narrowing the task.

## Read Next

- `reliability-patterns.md`
- `../../docs/04-context-and-chunking.md`
- `../../docs/05-structured-generation.md`
