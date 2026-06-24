# Foundation Models Reference

## Source Documents

This package is shaped by Apple's official Foundation Models documentation:

- [Foundation Models overview](https://developer.apple.com/documentation/FoundationModels)
- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- [Improving safety from generative model output](https://developer.apple.com/documentation/foundationmodels/improving-safety-from-generative-model-output)
- [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [Loading and using a custom adapter](https://developer.apple.com/documentation/FoundationModels/loading-and-using-a-custom-adapter-with-foundation-models)
- [WWDC26: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26: Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [WWDC26: Build agentic app experiences with the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/242/)
- [WWDC26: Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)
- [SwiftLLM WWDC26 Readiness](14-wwdc26-readiness.md)

## Platform Facts

Foundation Models is available on Apple platforms introduced with iOS, iPadOS, macOS, Mac Catalyst, and visionOS 26.

The package targets iOS 26, macOS 26, and visionOS 26 because the first useful version is built around Foundation Models and Apple Intelligence-era APIs.

The OS 27 generation expands Foundation Models with Private Cloud Compute, dynamic model context-size APIs, reasoning, image input, Dynamic Profiles, provider packages through `LanguageModel`, Evaluations, `fm`, Python SDK support, Core AI, and MLX integrations. SwiftLLM should prepare provider-neutral types for these concepts while keeping source compatible with the currently supported SDK.

## Model Availability

Apps must check availability before calling the model. Availability depends on:

- device eligibility
- Apple Intelligence being enabled
- model assets being downloaded and ready
- supported locale/language
- OS and SDK availability

SwiftLLM should not let app code treat the local model as guaranteed. Every high-level workflow should have a fallback path.

## Model Strengths

The on-device model is a good fit for:

- summarization
- entity extraction
- text understanding
- rewriting/refining text
- classification
- tag generation
- app-specific generation with tools
- structured output with guided generation

This maps well to Chime In's extraction needs and to many local-first Apple apps.

## Model Weaknesses

Apple's docs call out categories that are not ideal:

- basic math
- code generation
- fragile logical reasoning
- open-ended world knowledge
- large unbounded tasks

SwiftLLM should bias toward narrow tasks and deterministic post-processing. It should not encourage developers to ask the local model to be a general assistant.

## Context Window

The OS 26-era on-device foundation model has a 4,096-token context window per language model session.

Starting with newer platform releases, apps should not assume a single fixed context size. Apple now exposes context-size APIs on model values such as `SystemLanguageModel` and `PrivateCloudComputeLanguageModel`. Private Cloud Compute provides a 32K context window. Supported on-device context can vary by OS and hardware.

The context window includes:

- instructions
- prompts
- tool schemas
- tool arguments
- tool outputs
- generable schemas
- model responses
- session transcript history

This is the main architectural constraint. SwiftLLM should treat token budgeting as a first-class runtime concern, not an afterthought. Future Foundation Models support should query dynamic context size where available and fall back to conservative defaults only when exact information is unavailable.

Exact token counting through `SystemLanguageModel.tokenCount(for:)` is available on newer 26.x OS releases. SwiftLLM's Foundation Models adapter exposes an async token-count API and falls back to the core heuristic counter when exact counting is unavailable.

## Private Cloud Compute

Private Cloud Compute gives eligible apps access to a larger Apple Foundation Model through the Foundation Models API. Important properties:

- same session-style API as on-device Foundation Models
- no app-managed API key for Apple's PCC model
- Apple Intelligence availability is still required
- network connectivity is required
- per-user daily quota applies
- iCloud+ users can have higher limits
- the model has a 32K context window
- reasoning levels are available
- quota usage should be handled with persistent UI, not a dismissible alert

SwiftLLM should represent PCC as a distinct model locality. It can be privacy-preserving and OS-managed while still being cloud execution. Apps should be able to express policies such as local-only, local-preferred, PCC-allowed, or external-cloud-allowed.

`SwiftLLMFoundationModels` now includes pre-SDK readiness types for this layer:

- `FoundationModelExecutionTarget` distinguishes automatic, on-device, Private Cloud Compute, provider package, and custom local execution.
- `FoundationModelRuntimeProfile` records context window size, dynamic-context support, reasoning support, reasoning effort, and quota status.
- `FoundationModelQuotaStatus` models quota availability without assuming a particular Apple SDK property name.
- `FoundationModelGenerationOptions` carries requested execution target, reasoning effort, and requested context-window size. The live adapter ignores fields that cannot be mapped until the OS 27 SDK is available.

## Reasoning

PCC reasoning lets the model spend additional generated text before producing the final answer. The reasoning segment can improve quality, but it consumes context tokens and may increase latency. Deep reasoning can use more tokens than the final answer.

SwiftLLM should model reasoning as:

- a provider-neutral request preference
- a budget concern
- a token-usage field where supported
- an observable transcript or stream event where the provider exposes it

Reasoning should not be treated as a free quality upgrade.

`LLMTokenUsage`, `LLMTokenUsageReceipt`, and `EvaluationRunMetrics` include optional `cachedInputTokens` and `reasoningTokens` fields so PCC and provider-package usage reports can map into SwiftLLM without changing the public metrics shape later.

## Guided Generation

Guided generation lets developers define Swift structures with `@Generable` and ask the model to generate typed results.

Useful implications:

- Apps can avoid parsing free-form strings.
- Schemas constrain malformed output.
- Property names and guides consume context.
- Large nested schemas can be expensive.
- Array count limits matter for quality and token usage.

SwiftLLM should help developers keep schemas compact and validate the result after generation.

`SwiftLLMFoundationModels` exposes typed generation only inside `#if canImport(FoundationModels)` availability, so package tests and deterministic fallbacks can still compile on toolchains that do not ship the framework.

## Tool Calling

Tools let the model call app code to retrieve local data, perform app-specific work, or integrate with other Apple frameworks.

Tool calling is powerful but costly:

- tool descriptions consume tokens
- tool argument schemas consume tokens
- tool outputs consume tokens
- multiple tools can be called in parallel
- tool errors need explicit handling

SwiftLLM should encourage a small number of task-specific tools. If a tool is always needed, app code should often run it directly and pack the result into the prompt instead of asking the model to decide.

`SwiftLLMFoundationModels` exposes a typed tool path behind `#if canImport(FoundationModels)`:

- pass native `[any Tool]` values to `FoundationModelClient.respond(to:tools:)`
- pass native tools to typed guided generation through `respond(generating:request:tools:)`
- prewarm sessions with the same tool set through `prewarm(_:tools:)`
- use `FoundationModelToolConfiguration` when an app needs a small value wrapper for names and estimated definition-token cost

Provider-neutral `LLMClient` calls still reject tool requests for Foundation Models. That boundary is intentional: Apple's `Tool` protocol depends on concrete Swift associated types and app-owned code, so the generic adapter should not pretend it can execute arbitrary provider-neutral tools locally.

## Dynamic Profiles

Dynamic Profiles let a `LanguageModelSession` change active model, tools, instructions, generation options, and transcript treatment before each prompt. They are useful for multi-phase features that move between cheaper on-device work and higher-capability server work.

Important transcript rules from WWDC26:

- `historyTransform` applies a lossless per-request transform.
- Mutating session history is lossy and affects all profiles.
- Appending transcript entries usually preserves key-value cache behavior best.
- Rewriting history, changing instructions, or changing tools can invalidate caches.
- Tool calling can be allowed, disallowed, or required.
- Required tool calling needs an exit condition.
- Preserving transcript state after an error is advanced and requires app repair logic.

SwiftLLM should translate these concepts into context compiler and workflow primitives rather than copying Apple's API surface directly. The package needs app-neutral concepts for context snapshots, compaction previews, cache-aware diagnostics, tool calling mode, and transcript error policy.

## Provider Packages

The OS 27 Foundation Models provider model is based on `LanguageModel` and `LanguageModelExecutor`:

- `LanguageModel` describes capabilities and configuration.
- `LanguageModelExecutor` handles prewarm, request translation, streaming, usage, metadata, and errors.
- Executors can be cached by configuration inside a session.
- Providers receive the full transcript on every request and decide whether history was appended or rewritten.
- Providers can stream metadata, usage, text, tool calls, reasoning, and custom segments.

SwiftLLM's provider-neutral layer should stay compatible with that shape:

- richer endpoint descriptors
- stream events for metadata and usage deltas
- token usage fields for cached input and reasoning tokens
- provider error normalization
- explicit privacy and authentication boundaries
- no hidden app-local tool execution

## Context And Agent-Like Planning

Apple's session model gives SwiftLLM enough primitives to build focused, pseudo-agent workflows
without adopting a heavyweight agent framework:

- `Instructions` define trusted role and behavior context.
- `Prompt` carries the user/app task payload.
- `Transcript` can rehydrate an existing session history when a workflow really needs continuity.
- `Tool` exposes app code for local retrieval or side-effect boundaries.
- `@Generable`/guided generation constrains structured outputs.
- `prewarm(promptPrefix:)` lets apps reduce latency for predictable prompt prefixes.

SwiftLLM models this through `LLMContextPlan`. A context plan records which parts of a request occupy
the model's context window, which parts are trusted, whether session transcript rehydration is
expected, whether tool definitions are available to the model, and whether the app should prefetch
context before generation. This keeps Chime In-style workflows explainable: app code can run local
search and deterministic analysis first, feed compact context to Foundation Models, and reserve native
tool calling for cases where model-directed lookup is genuinely useful.

The generic Foundation Models client deliberately treats tool items in a context plan as planning metadata. It can carry context plans, budget them, and expose required capabilities; native `Tool` execution is available only through the typed Foundation Models adapter because Apple's `Tool` protocol requires concrete Swift types.

## Safety and Guardrails

Foundation Models includes built-in safety behavior, but app-specific safety is still required.

SwiftLLM should support:

- fixed-task prompt contracts
- deny lists where appropriate
- structured output boundaries
- validation hooks
- safety evaluation corpora
- local feedback capture
- refusal and guardrail error handling

The package should not bypass safety controls casually.

The adapter normalizes guardrail, refusal, unsupported-locale, context-window, decoding, rate-limit, concurrent-request, unsupported-guide, asset, tool-call, and generic provider failures into `FoundationModelFailure` and maps each to a package-level `FallbackReason`.

## Performance

Apple's Foundation Models instrument exposes model loading, prompt processing, inference, tool calling, and token usage. The docs recommend profiling with additional CPU and power instruments.

SwiftLLM should make performance easier to understand by preserving:

- prompt version
- provider metadata
- token estimates
- measured token counts when available
- request duration
- fallback reason
- validation failures

## Model Updates

Apple updates the system model with OS releases. Documentation already notes model changes aligned with OS version ranges and recommends testing prompts with new model versions.

SwiftLLM should assume model behavior is not static. Prompt contracts and evaluation corpora must be versioned.
