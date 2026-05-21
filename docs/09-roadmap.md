# Roadmap

## Phase 0: Private Scaffold

Status: started.

- Create package targets.
- Add XcodeGen showcase shell.
- Add durable docs and agent docs.
- Add initial token budget, chunking, prompt, metadata, validation, and evaluation primitives.

## Phase 1: Foundation Models Adapter

Status: completed for the first usable adapter slice.

Build a real adapter around Foundation Models:

- availability and locale normalization: implemented
- token counter adapter: implemented with exact counting when available and heuristic fallback otherwise
- prewarm API: implemented
- typed guided generation wrapper: implemented behind `canImport(FoundationModels)`
- text generation wrapper: implemented
- error normalization: implemented
- context-window handling: normalized into fallback metadata
- refusal/guardrail handling: normalized, with refusal explanation capture when available
- response metadata capture: implemented

Acceptance criteria:

- Chime In can call Foundation Models through SwiftLLM without owning framework-specific error handling.
- Tests can exercise unavailable/fallback behavior without importing Foundation Models.

Remaining refinements can happen in later phases: Foundation Models tool-call wrappers, feedback attachment capture, richer token accounting for instructions/schemas/tools, and typed diagnostics reports.

## Phase 2: Structured Generation Toolkit

Status: completed for the first provider-neutral toolkit slice.

Add generic structured generation support:

- prompt contracts: implemented through `PromptContract` and `StructuredGenerationContract`
- schema descriptors: implemented through `StructuredGenerationSchema` and `StructuredGenerationField`
- candidate wrappers: implemented through `StructuredGenerationCandidate`
- validation hooks: implemented through `StructuredGenerationValidator`
- repair policy: implemented as declarative `StructuredGenerationRepairPolicy`
- fallback policy: implemented through `StructuredGenerationFallbackPolicy`
- evidence fields: implemented through `EvidenceSource`, `EvidenceSpan`, and `StructuredGenerationSourceContext`

Acceptance criteria:

- Chime In extraction prompt compilation can be expressed using SwiftLLM primitives.
- Generated candidates can be validated before becoming Chime In review drafts.

Remaining refinements can happen in later phases: automatic repair loops, richer structured assertion DSLs, source-range helpers for transcript timestamps, and provider-specific schema cost accounting.

## Phase 3: Context Pipeline

Status: completed for the first context pipeline slice.

Improve long-input handling:

- sentence/paragraph-aware chunker: implemented through `BoundaryAwareTextChunker`
- transcript-segment chunker: implemented through `TranscriptSegment`, `TranscriptChunk`, and `TranscriptChunker`
- overlap policies: implemented for text units and transcript segments
- map/reduce orchestration: implemented through `MapReducePipeline`
- merge and dedupe helpers: implemented through `MergePolicy`
- context packing strategies: implemented through `.scoreDescending` and `.scoreDensity`

Acceptance criteria:

- Long Chime In recordings can be processed without prefix/suffix truncation.
- Intermediate chunk outputs preserve source evidence.

Remaining refinements can happen in later phases: concurrent map execution with resource controls, richer transcript timestamp evidence helpers, chunk diagnostics, domain-specific merge policies, and automatic repair loops over failed chunks.

## Phase 4: Local RAG

Status: completed for the first dependency-free retrieval slice.

Add local retrieval abstractions:

- retriever protocol: implemented through `LocalRetriever` and `AnyLocalRetriever`
- retrieved snippet model: expanded with source metadata, ranges, and required-snippet handling
- source references: implemented through `SourceReference` and `RetrievableDocument`
- packer strategies: implemented through `.sourceDiverse`
- citation output helpers: implemented through `SnippetCitation` and `CitationContextRenderer`
- local RAG pipeline: implemented through `LocalRAGPipeline` and `LocalRAGResult`
- optional GRDB/SQLite integration target if needed: deferred until a real app integration needs it

Acceptance criteria:

- Apps can plug in their own local index without depending on a server.
- The showcase demonstrates query -> snippets -> packed prompt.

Remaining refinements can happen in later phases: SQLite/GRDB adapters, embedding-backed retrievers where platform APIs make sense, richer citation formatting, query rewriting, source-diversity budget controls, and retrieval diagnostics.

## Phase 5: Evaluation And Diagnostics

Status: completed for the first reportable evaluation slice.

Make evals a first-class product:

- structured assertion DSL: implemented through `TextEvaluationAssertion`, `StructuredEvaluationAssertion`, and `StructuredOutputEvaluator`
- prompt version matrix: implemented through `PromptVersionEvaluationReport` and `PromptVersionEvaluationMatrix`
- model availability/fallback matrix: implemented through `ModelFallbackMatrix`
- safety probe support: partially covered through text/structured assertions and fallback metadata; richer probe types remain future work
- token and latency report models: implemented through `EvaluationRunMetrics`
- JSON report output: implemented on prompt reports and debug bundles
- local-only debug bundle format: implemented through `LocalDebugBundle`

Acceptance criteria:

- Chime In can run extraction regression cases against local model output and deterministic fallbacks.
- Prompt changes produce reviewable reports.

Remaining refinements can happen in later phases: first-class safety probe models, richer structured assertion helpers, file-writing helpers with explicit redaction policy, report diffing, JUnit/CI output, and DocC examples.

## Phase 6: Provider-Neutral Client Layer

Status: completed for the first private adapter slice.

Add Swift-native provider access that can support local Foundation Models plus explicitly configured external providers:

- provider-neutral `LLMClient` protocol: implemented
- `LLMRequest`, `LLMResponse`, `LLMMessage`, response formats, tools, tool calls, streaming events, and normalized client errors: implemented
- provider capability negotiation: implemented through `LLMClientCapabilities`
- type-erased `AnyLLMClient`: implemented
- fallback `LLMRouter`: implemented with retryable error policy and before-output streaming fallback
- high-level `LLMPipeline` over prompt contracts and optional local RAG: implemented
- Foundation Models conformance to `LLMClient`: implemented
- OpenAI Responses API adapter: implemented
- Anthropic Messages API adapter: implemented
- injectable response and streaming HTTP transports for provider tests: implemented
- provider-native tool result message mapping: implemented for OpenAI `function_call_output` and Anthropic `tool_result`

Acceptance criteria:

- A Swift app can initialize Foundation Models, OpenAI, Anthropic, or a router from the same core API.
- Provider adapter tests do not require real API keys or network calls.
- API key storage remains an app concern.

Remaining refinements can happen in later phases: provider-specific structured output affordances, stricter schema validation, request/response trace redaction, retry/backoff policy hooks, and richer token/cost accounting for tool-heavy conversations.

## Phase 7: Open Source Preparation

Before public release:

- choose license
- audit docs for private Chime In details
- finalize API stability policy
- expand DocC documentation
- harden CI across supported Xcode versions
- finalize contribution guide details
- add security reporting contact
- add sample screenshots
- tag `0.1.0`

## Later: Custom Adapters

Custom adapters may become useful, but they should not lead the package.

A future adapter manager could handle:

- entitlement checks
- adapter availability
- adapter version compatibility
- download/asset status
- base model version compatibility
- fallback to base model

This should wait until the core orchestration layer is useful.
