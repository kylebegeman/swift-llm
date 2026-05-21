# Changelog

## Unreleased

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
