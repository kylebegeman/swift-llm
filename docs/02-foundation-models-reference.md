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

## Platform Facts

Foundation Models is available on Apple platforms introduced with iOS, iPadOS, macOS, Mac Catalyst, and visionOS 26.

The package targets iOS 26, macOS 26, and visionOS 26 because the first useful version is built around Foundation Models and Apple Intelligence-era APIs.

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

Apple's on-device foundation model has a 4,096-token context window per language model session.

The context window includes:

- instructions
- prompts
- tool schemas
- tool arguments
- tool outputs
- generable schemas
- model responses
- session transcript history

This is the main architectural constraint. SwiftLLM should treat token budgeting as a first-class runtime concern, not an afterthought.

Exact token counting through `SystemLanguageModel.tokenCount(for:)` is available on newer 26.x OS releases. SwiftLLM's Foundation Models adapter exposes an async token-count API and falls back to the core heuristic counter when exact counting is unavailable.

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
