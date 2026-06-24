# Changelog

## 1.0.0 - 2026-06-24

- Split core client, router, context, retrieval, workflow, structured generation, Foundation Models, evaluation, and test coverage into smaller feature-focused files without changing behavior.
- Added bounded parallel map-reduce execution with input-order preservation for chunk pipelines.
- Added `LLMRunReceipt`, `LLMInstrumentedResponse`, router receipt callbacks, and redacted receipt support in `LocalDebugBundle`.
- Added `LLMContextCompiler` for fixed-cost context accounting, retrieved-snippet packing, dropped-snippet diagnostics, citation rendering, context plans, and compiled prompts.
- Updated `LLMPipeline` to use `LLMContextCompiler` internally and expose context compilation diagnostics.
- Added `LLMEndpointRegistry`, `LLMEndpoint`, and `LLMRoutingPlan` for provider-neutral endpoint registration and router construction.
- Added Foundation Models pre-SDK readiness types for execution targets, Private Cloud Compute runtime profiles, quota status, reasoning effort, and dynamic context-size hints.
- Added cached-input and reasoning-token accounting to `LLMTokenUsage`, OpenAI and Anthropic adapters, run receipts, and evaluation metrics.
- Fixed required local retrieval source precedence so user-required sources override allow-list omissions while explicit exclusions still win.
- Replaced the initial license stub with Apache-2.0.
- Replaced the initial security stub with a public vulnerability reporting policy and LLM-specific security scope.
- Reworked the README with badges, diagrams, quick-start examples, provider boundaries, evaluation guidance, and WWDC26 readiness notes.
- Updated contributing guidance for public package boundaries, Swift concurrency expectations, verification, and OS 27 SDK gating.
- Added durable WWDC26 readiness documentation covering Private Cloud Compute, reasoning, Dynamic Profiles, provider packages, Core AI, MLX, Evaluations, fm, and Python SDK implications.
- Updated the Foundation Models reference, roadmap, and open-source readiness docs for OS 27 planning and public-release polish.

## 0.1.0-rc.2

- Split the OpenAI and Anthropic adapters into transport, request encoding, response decoding, streaming, and support files without changing their public client APIs.
- Added typed Foundation Models native tool wrappers for text generation, guided generation, and prewarming behind `canImport(FoundationModels)`.
- Documented the release-candidate tag flow for private incubation deploys.

## 0.1.0-rc.1

- Initial private package scaffold.
- Added `SwiftLLM`, `SwiftLLMFoundationModels`, `SwiftLLMOpenAI`, `SwiftLLMAnthropic`, and `SwiftLLMEvaluation` products.
- Added XcodeGen showcase shell.
- Added durable docs, scratch policy, and agent routing docs.
- Completed the first Foundation Models adapter slice with availability normalization, token counting, prewarming, text generation, typed guided generation entrypoints, error normalization, fallback mapping, and SDK-independent fake-client tests.
- Completed the first structured generation toolkit slice with schema descriptors, structured contracts, evidence sources/spans, candidate wrappers, validation issues/results, generic validators, repair/fallback policies, and a provider-neutral pipeline.
- Completed the first context pipeline slice with boundary-aware text chunking, transcript segment chunking with timestamps, score-density context packing, map/reduce orchestration, and merge/dedupe policy helpers.
- Completed the first local RAG slice with source references, async retriever abstractions, deterministic keyword retrieval, source-diverse packing, citation rendering, and a provider-neutral local RAG pipeline.
- Completed the first evaluation and diagnostics slice with text assertions, structured output assertions, prompt-version reports, fallback matrices, run metrics, JSON output, and redacted local debug bundles.
- Completed the first provider-neutral client slice with `LLMClient`, `AnyLLMClient`, `LLMRouter`, shared request/response/tool/schema types, Foundation Models conformance, OpenAI Responses adapter, Anthropic Messages adapter, injectable HTTP transports, and provider adapter tests.
- Hardened the provider-neutral layer by preserving prompt-version metadata across adapters, rejecting unsupported Foundation Models features instead of silently ignoring them, routing provider streaming through injectable transports, keeping API keys out of public stored properties, and allowing required local retrieval sources for empty queries.
- Added first-class provider capabilities, retryable router fallback policy, before-output streaming fallback, native OpenAI/Anthropic tool-result history mapping, and shared provider test support.
- Fixed audit findings around persisted message decoding, exact short grounding evidence, required local retrieval priority, OpenAI failed response/stream errors, and Anthropic streamed tool-call events.
- Added Foundation Models context planning through `LLMContextPlan`, context surfaces, trust levels, session policy, tool execution policy, and context budget reporting.
- Added workflow orchestration through `LLMWorkflow`, `LLMStep`, workflow events, intermediate outputs, budget reports, and step helpers for deterministic transforms, retrieval, context planning, model generation, validation, and repair/fallback.
- Polished production-readiness docs, provider file organization, public API comments, issue templates, and agent doc links.
