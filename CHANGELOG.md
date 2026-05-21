# Changelog

## Unreleased

- Initial private package scaffold.
- Added `SwiftLLM`, `SwiftLLMFoundationModels`, and `SwiftLLMEvaluation` products.
- Added XcodeGen showcase shell.
- Added durable docs, scratch policy, and agent routing docs.
- Completed the first Foundation Models adapter slice with availability normalization, token counting, prewarming, text generation, typed guided generation entrypoints, error normalization, fallback mapping, and SDK-independent fake-client tests.
- Completed the first structured generation toolkit slice with schema descriptors, structured contracts, evidence sources/spans, candidate wrappers, validation issues/results, generic validators, repair/fallback policies, and a provider-neutral pipeline.
- Completed the first context pipeline slice with boundary-aware text chunking, transcript segment chunking with timestamps, score-density context packing, map/reduce orchestration, and merge/dedupe policy helpers.
- Completed the first local RAG slice with source references, async retriever abstractions, deterministic keyword retrieval, source-diverse packing, citation rendering, and a provider-neutral local RAG pipeline.
- Completed the first evaluation and diagnostics slice with text assertions, structured output assertions, prompt-version reports, fallback matrices, run metrics, JSON output, and redacted local debug bundles.
