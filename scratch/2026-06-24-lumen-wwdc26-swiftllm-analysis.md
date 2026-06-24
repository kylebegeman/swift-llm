# SwiftLLM Planning Analysis: Lumen, WWDC26, and Open Source Polish

Date: 2026-06-24  
Status: working planning note  
Scope: SwiftLLM package review, Lumen feature mining, WWDC26 Foundation Models research, Swift 6.2/6.3 polish, open-source readiness

## Executive Summary

SwiftLLM is already pointed in the right direction. The package has a clean provider-neutral core, explicit Foundation Models isolation, OpenAI and Anthropic adapters, context planning, local RAG, structured generation, workflows, and evaluation diagnostics. The best next move is not to replace the architecture. It is to add a few durable primitives that make the existing architecture more capable:

- A richer model endpoint and routing layer for on-device, Private Cloud Compute, external cloud, and local server models.
- A context compiler v2 that turns the current context plan and chunking pieces into a reusable compilation, compaction, and diagnostics pipeline.
- A run receipt and diagnostics model that records model choice, context decisions, validation, repairs, fallbacks, quota state, redaction, and performance.
- WWDC26-ready Foundation Models abstractions that can support iOS 27 Private Cloud Compute, dynamic context size, reasoning levels, quota handling, dynamic profiles, third-party model providers, and the Evaluations framework once the SDK is installed.
- Open-source polish: license replacement, security policy, public README, DocC expansion, smaller files, CI hardening, API stability audit, and examples.

The repo should stay app-neutral. Lumen has useful patterns, but SwiftLLM should translate them into general library primitives rather than copying cockpit or agent UX concepts.

## Inputs Reviewed

SwiftLLM local sources and docs:

- `llm/START_HERE.md`, `llm/capabilities/*`, and `llm/playbooks/*`
- `README.md`, `Package.swift`, `.github/*`, `scripts/validate.sh`
- Durable docs in `docs/00-overview.md` through `docs/13-provider-adapters.md`
- Public source targets under `Sources/SwiftLLM*`
- Tests under `Tests/SwiftLLMTests`
- `LICENSE.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`

Lumen local sources and docs, read-only because the Lumen worktree has unrelated local changes:

- `/Users/kyle/Developer/products/lumen/AGENTS.md`
- `README.md`
- `docs/llm/START_HERE.md`
- `docs/project/lumen-cockpit-implementation/*`
- `packages/contracts/src/contextEngine.ts`
- `apps/server/src/contextEngine/Layers/ContextEngine.ts`
- `packages/contracts/src/knowledge.ts`
- `packages/contracts/src/modelEndpoints.ts`
- `packages/contracts/src/loopRuntime.ts`
- `packages/contracts/src/productExpansion.ts`

Local WWDC Foundation transcript bundle:

- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-240.txt`: Siri and App Intents in the 27 releases
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-241.txt`: What's new in the Foundation Models framework
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-242.txt`: Build agentic app experiences with the Foundation Models framework
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-297.txt`: Visual Intelligence app integration
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-319.txt`: Build with the new Apple Foundation Model on Private Cloud Compute
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-324.txt`: Integrate on-device AI models into your app using Core AI
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-325.txt`: Core AI model authoring and optimization
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-334.txt`: Build AI-powered scripts with the fm CLI and Python SDK
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-339.txt`: Bring an LLM provider to the Foundation Models framework

Official/current research:

- Apple Intelligence What's New: https://developer.apple.com/apple-intelligence/whats-new/
- Foundation Models docs: https://developer.apple.com/documentation/foundationmodels
- Private Cloud Compute docs: https://developer.apple.com/private-cloud-compute/
- "What's new in the Foundation Models framework", WWDC26 session 241: https://developer.apple.com/videos/play/wwdc2026/241/
- "Build with the new Apple Foundation Model on Private Cloud Compute", WWDC26 session 319: https://developer.apple.com/videos/play/wwdc2026/319/
- "Build agentic app experiences with the Foundation Models framework", WWDC26 session 242: https://developer.apple.com/videos/play/wwdc2026/242/
- "Bring an LLM provider to the Foundation Models framework", WWDC26 session 339: https://developer.apple.com/videos/play/wwdc2026/339/
- "Meet the Evaluations framework", WWDC26 session 298: https://developer.apple.com/videos/play/wwdc2026/298/
- "Create robust evaluations for agentic apps", WWDC26 session 299: https://developer.apple.com/videos/play/wwdc2026/299/
- "Debug and profile agentic app experiences with Instruments", WWDC26 session 243: https://developer.apple.com/videos/play/wwdc2026/243/
- Swift 6.2 release notes: https://swift.org/blog/swift-6.2-released/
- Swift 6.3 release notes: https://swift.org/blog/swift-6.3-released/

## Current SwiftLLM Baseline

The current package shape is strong:

- `SwiftLLM`: provider-neutral primitives, requests, responses, routing, context, RAG, structured generation, validation, workflows.
- `SwiftLLMFoundationModels`: Foundation Models adapter and typed guided generation/tool wrappers behind `canImport(FoundationModels)`.
- `SwiftLLMOpenAI`: OpenAI Responses API adapter.
- `SwiftLLMAnthropic`: Anthropic Messages API adapter.
- `SwiftLLMEvaluation`: prompt evaluations and local diagnostics.

Current strengths:

- Public types are already heavily `Sendable`.
- Provider HTTP clients have injectable transports and focused tests.
- Core package has no provider keys, telemetry, or network behavior.
- Foundation Models imports are isolated to `SwiftLLMFoundationModels`.
- Unsupported Foundation Models request features are rejected rather than silently ignored.
- Context planning, structured generation, local RAG, and workflow orchestration are already usable primitives.

Current constraints:

- `FoundationModelDefaults.contextWindowTokens` is still OS 26-era and static at 4,096 tokens.
- `FoundationModelClient` has no concept of Private Cloud Compute, reasoning levels, quota state, or dynamic `contextSize`.
- `LLMClientCapabilities` is good for feature checks, but not rich enough for endpoint health, locality, quota, cost, privacy, explicit routing policy, or model repair actions.
- `ContextPipeline` and `LLMContextPlan` are useful but not yet a full compiler with snapshots, inclusion modes, quality signals, and compaction previews.
- Some files are production-large: `LLMWorkflow.swift`, `FoundationModelSupport.swift`, `StructuredGeneration.swift`, `LLMClient.swift`, and the main test files.
- Open-source public files are intentionally placeholder level: license, security policy, and public README all need release polish.

## WWDC26 Implications

Apple's 2026 changes are significant enough that SwiftLLM should treat OS 27 as a first-class planning target, while keeping source compilable on the currently installed SDK.

### Foundation Models Becomes a Model Abstraction Layer

Apple now describes Foundation Models as a Swift API for any large language model, including on-device Apple models, Apple Foundation Models on Private Cloud Compute, cloud models such as Claude and Gemini, and any provider that conforms to the `LanguageModel` protocol. WWDC26 session 339 adds provider-facing primitives through `LanguageModelExecutor`.

SwiftLLM impact:

- Keep `LLMClient` provider-neutral, but add a model endpoint descriptor that can represent Foundation Models providers, Apple PCC, external APIs, local servers, and custom `LanguageModel` integrations.
- Do not make `SwiftLLMFoundationModels` a thin wrapper around only `SystemLanguageModel`. It should become the adapter for Apple Foundation Models framework sessions, including on-device, PCC, and custom Foundation Models providers.

### Private Cloud Compute Changes the Default Cloud Story

Private Cloud Compute now gives eligible apps access to Apple Foundation Models on Apple's privacy-preserving server infrastructure. Official Apple material says eligible App Store Small Business Program members with fewer than 2 million total first-time App Store downloads can access this at no cloud API cost. The model uses Foundation Models APIs, requires no app-managed API key, and has per-user daily limits with higher limits for iCloud+ users.

SwiftLLM impact:

- Add first-class `LLMLocality.privateCloudCompute`.
- Add quota status types so apps can surface "available", "approaching limit", "limit reached", and "increase suggestion available" without hard-coding Apple-only UI logic.
- Add routing policy that can prefer on-device for low-latency/offline/private tasks and PCC for higher-reasoning or larger-context tasks.
- Keep external cloud adapters explicit and opt-in. PCC is still networked cloud execution, even if privacy-preserving and OS-managed.

### Context Size and Reasoning Are Dynamic

WWDC26 material shows:

- OS 26-era on-device context was 4,096 tokens.
- Newer OS 27 on-device models can expose larger dynamic context sizes, including 8,192 tokens on supported devices.
- `PrivateCloudComputeLanguageModel` supports a 32K context.
- Both `SystemLanguageModel` and `PrivateCloudComputeLanguageModel` expose `contextSize`.
- PCC supports reasoning levels such as light, moderate, and deep. Reasoning consumes context tokens and can be observed through the transcript.

SwiftLLM impact:

- Replace hard-coded Foundation Models context-window assumptions with a dynamic context-size query where available.
- Model reasoning effort as a provider-neutral option, but avoid promising exact semantics across providers.
- Include reasoning-token budget in `LLMContextBudgetReport`.
- Treat reasoning as a transcript segment where provider support exists, not just as an invisible request parameter.
- Add diagnostics that show how much budget went to system instructions, prompt, retrieval, transcript, tools, expected output, and reasoning reserve.

### Dynamic Profiles Map Directly to SwiftLLM's Context and Workflow Work

WWDC26 session 242 introduces dynamic profiles, dynamic instructions, model selection per phase, history transforms, lifecycle modifiers, session properties, baton-pass orchestration, phone-a-friend/skills, and tool calling modes.

SwiftLLM impact:

- Extend workflows with a phase/profile concept that can choose model, instructions, tools, context transform, and validation policy per step.
- Treat history transforms as a library-level context compilation feature: lossless transform for a single request, lossy compaction only when explicitly persisted by the app.
- Add reusable handoff metadata for "local first, cloud escalation" and "specialist model" flows.
- Add explicit transcript mutation policy. Dynamic Profiles distinguish lossless per-request `historyTransform` behavior from lossy mutable history updates, and that split maps cleanly to SwiftLLM's context compiler.
- Add cache-awareness to context snapshots. Appending transcript entries preserves key-value cache behavior best; rewriting history, changing tools, or changing instructions can invalidate caches and increase latency.
- Add `LLMToolCallingMode` with allowed, disallowed, and required. The required mode needs exit-condition diagnostics because it can create tool-call loops.
- Add transcript error handling policy with revert and preserve modes. Preserve is advanced and should surface a diagnostic warning when the transcript needs app repair.

### Evaluations Becomes a Platform Feature

Xcode 27 and the Evaluations framework provide dataset-driven evaluation, metric aggregation, qualitative model judges, hill-climbing, synthetic data generation, and agentic app evaluation.

SwiftLLM impact:

- Keep `SwiftLLMEvaluation` useful without Xcode 27, but design adapters that can export/import evaluation cases and reports compatible with Apple's Evaluations style.
- Add model-as-judge and comparative evaluation primitives only behind explicit configuration, because they introduce provider choice, cost, privacy, and nondeterminism.
- Strengthen evaluation coverage around prompts, validators, RAG, context compaction, tool calls, fallback routing, and PCC escalation.

### Provider Packages Shape the Adapter Story

WWDC26 session 339 clarifies how Foundation Models provider packages work:

- A `LanguageModel` describes capabilities and configuration.
- A `LanguageModelExecutor` performs prewarm and streaming responses.
- Executors are cached by hashable configuration inside a session, so provider packages can preserve loaded weights, connections, or key-value cache state.
- Executors receive a full transcript each request and decide whether new entries were appended or prior entries changed.
- Streaming should send metadata and usage updates early when available, then text/tool/reasoning/custom segment events.
- Provider packages should prefer built-in `LanguageModelError` cases when they fit.
- Cloud provider packages should avoid raw API-key initializers where possible and should document privacy implications clearly.
- Custom segments and response metadata are the extension points for new modalities, citations, server-side tools, performance metrics, and provider-specific details.

SwiftLLM impact:

- `LLMStreamEvent` should eventually support metadata and usage deltas before completion.
- `LLMTokenUsage` should grow beyond input/output tokens to include cached input tokens and reasoning tokens.
- Provider adapters should expose typed metadata accessors instead of only string dictionaries where stable fields exist.
- Future Foundation Models provider bridges should preserve transcript-entry identity enough to support append detection and cache diagnostics.
- Server-side tools should be represented as provider capabilities and response metadata, but app-local tool execution must remain explicit.

### Core AI, MLX, and Custom Local Models

The Core AI sessions show a future path for custom on-device models:

- Core AI can run local models efficiently on Apple Silicon through a modern Swift API.
- Core AI model loading includes specialization and cache behavior that should be prepared outside user-interactive flows.
- Transformer-style key-value caches can be modeled as state to avoid recomputing full history.
- The Core AI models repository includes higher-level APIs for model families and a Core AI language model that can plug into Foundation Models.
- MLX language models are another open-source route for local models.

SwiftLLM impact:

- Do not add a Core AI dependency to the core package now.
- Make endpoint descriptors general enough to describe local bundled models, local downloaded models, and Foundation Models language models.
- Add future fields for prewarm cost, specialization status, model asset size, and cache readiness.

### App Intents, Visual Intelligence, and Spotlight

The App Intents and Visual Intelligence transcripts are mostly app-layer material, but they clarify where SwiftLLM should integrate rather than expand:

- App entities, schemas, indexed entities, Spotlight, `Transferable`, and view annotations belong in apps.
- Visual Intelligence queries and system store integrations belong in apps.
- SwiftLLM should not own App Intents schemas, Siri UX, or Visual Intelligence provider code.
- SwiftLLM can provide context, retrieval, evidence, and evaluation primitives that apps use behind App Intents, Spotlight search, and Visual Intelligence flows.

Potential future docs:

- "Using SwiftLLM behind App Intents"
- "Using SwiftLLM with Core Spotlight RAG"
- "Evaluating Siri and Visual Intelligence powered LLM flows"

### fm CLI and Python SDK Suggest a Prompt Development Workflow

The fm CLI and Python SDK sessions are useful for documentation:

- `fm chat` is a quick way to test prompts interactively.
- `fm respond` can use on-device or PCC models, images, and schemas.
- The Python SDK supports text/image inputs, streaming, guided generation, and tool calling.
- Python notebooks are useful for generating outputs, grading them, and plotting evaluation results before porting prompts back to Swift.

SwiftLLM impact:

- Add README guidance that SwiftLLM works well with an external prompt iteration loop: prototype prompts with `fm` or notebooks, then encode stable prompts as `PromptContract` values and evaluate them with `SwiftLLMEvaluation`.
- Add future import/export helpers only if real eval datasets prove the need.

### Instruments and Trace Privacy Should Shape Diagnostics

WWDC26 session 243 highlights richer Foundation Models Instruments support, including sessions, requests, inferences, and tool calls. Apple warns that traces can include sensitive prompt data.

SwiftLLM impact:

- Debug bundles should remain local by default and redacted unless explicitly configured otherwise.
- Add trace/receipt levels: metadata only, redacted text, full local debug.
- Make trace export app-controlled, not automatic.

## Lumen Ideas Worth Translating

### 1. Context Compiler With Inclusion Modes

Lumen has a mature context engine with source targets, readiness, privacy levels, inclusion modes, compile options, snapshots, token estimates, quality signals, auto-shrink, and compaction preview.

SwiftLLM translation:

- Add `LLMContextCompiler` as a layer above current chunkers and `LLMContextPlan`.
- Introduce app-neutral source kinds such as document, transcript, selection, diff, memory, tool result, retrieval hit, and generated summary.
- Add inclusion modes such as full, slice, summary, metadata, and exclude.
- Add source priority and optionality so compaction can degrade optional sources before removing them.
- Persist or return `LLMContextSnapshot` with sections, token estimates, omitted sources, quality signals, and reuse estimates.
- Add `LLMCompactionPreview` to show what changed before an app accepts a lossy compaction.

Why this matters:

SwiftLLM currently has the raw ingredients. This would make the library feel like a serious production context system, not only a collection of chunking utilities.

### 2. Model Endpoint Registry and Health

Lumen's model endpoint descriptors include capability profiles, context window, max output, streaming, tools, structured output, observed speed, reliability, cost, secret refs, routing metadata, preferred use cases, disallowed use cases, concurrency limits, timeouts, health, and probe results.

SwiftLLM translation:

- Add `LLMModelEndpointDescriptor`.
- Add `LLMEndpointHealth` and `LLMModelProbeResult`.
- Add `LLMRoutingIntent` for tasks such as summarize, extract, reason, chat, classify, retrieve, repair, evaluate, and tool-use.
- Add policy knobs for locality, privacy, cost class, latency target, required capabilities, preferred endpoints, and disallowed endpoints.

Why this matters:

This is the bridge between on-device, PCC, OpenAI, Anthropic, local server models, and future Foundation Models providers.

### 3. Run Receipts and Diagnostics

Lumen's command receipts and adaptive reports record actors, risk, approvals, resources, status, durations, token/cost usage, rollback, provider observations, acceptance metrics, and launch states.

SwiftLLM translation:

- Add `LLMRunReceipt` for generation, context compilation, retrieval, validation, repair, fallback, and evaluation.
- Include provider id, model id, locality, capabilities, quota snapshot, context snapshot id, token budget, timings, validation summary, fallback path, redaction level, and error taxonomy.
- Keep receipts local and serializable.

Why this matters:

Open-source adopters need to debug model behavior without guessing. Receipts also make README examples more credible because they show how to inspect what happened.

### 4. Knowledge Source Sets and Retrieval Traces

Lumen's knowledge contracts model sources, items, citations, claims, source sets, retrieval hits, omitted sources, Deep Research requests, and reports.

SwiftLLM translation:

- Extend `LocalRAG` with source sets and retrieval traces.
- Add citation confidence and omitted-source reasons.
- Add a generic `EvidenceRecord` type that can be reused by structured generation validators and evaluation reports.

Why this matters:

SwiftLLM already has evidence and citations, but source sets and omitted-source records would make grounded generation easier to audit.

### 5. Evaluation Reports for Agentic and Multi-Step Work

Lumen's loop runtime has evaluator references, verdicts, summaries, evidence, and receipt ids.

SwiftLLM translation:

- Extend `PromptEvaluationReport` with workflow step results, receipt ids, context snapshot ids, model endpoint ids, and fallback paths.
- Add comparative reports for on-device vs PCC vs external provider outputs.
- Add privacy-aware exported datasets for prompt iteration.

Why this matters:

This aligns directly with Apple's new Evaluations framework and gives SwiftLLM a credible quality story.

### 6. Policies, Not App-Specific Approval UX

Lumen's decision and approval layer is useful, but cockpit approval UX should not move into SwiftLLM.

SwiftLLM translation:

- Add app-neutral policy results for tool execution, cloud escalation, sensitive source inclusion, and fallback.
- Let apps decide whether those policies become confirmations, logs, UI badges, or background behavior.

## Proposed SwiftLLM Roadmap

### Phase 0: Baseline Verification

Goal: know the current state before broad edits.

Tasks:

- Run `swift test`.
- Run `swift build -Xswiftc -warnings-as-errors`.
- Run `./scripts/validate.sh` if local XcodeGen and SDK state allow.
- Record any baseline failures before changing behavior.

### Phase 1: File Organization With No Behavior Changes

Goal: reduce maintenance cost without changing public APIs.

Tasks:

- Split `Sources/SwiftLLM/Workflow/LLMWorkflow.swift` into workflow models, runtime, events, steps, and step factories.
- Split `Sources/SwiftLLMFoundationModels/FoundationModelSupport.swift` into availability, options, client protocol, live implementation, provider-neutral conformance, and native tool wrappers.
- Split `Sources/SwiftLLM/StructuredGeneration/StructuredGeneration.swift` into schema, evidence, validation, repair policy, and pipeline files.
- Split the largest test files by feature area.
- Add `@_documentation(visibility: internal)` only if DocC noise becomes a problem.

Verification:

- `swift test`
- `swift build -Xswiftc -warnings-as-errors`

### Phase 2: Diagnostics and Receipts

Goal: make every generation, retrieval, validation, and fallback path inspectable.

Tasks:

- Add `LLMRunReceipt`.
- Add `LLMTraceRedactionLevel`.
- Add receipt ids to workflow events and evaluation reports.
- Extend debug bundle JSON with context snapshots and fallback paths.
- Add tests that verify sensitive values are redacted by default.

Verification:

- Unit tests for receipt serialization and redaction.
- Snapshot-style JSON fixture tests for debug bundles.

### Phase 3: Context Compiler v2

Goal: turn context planning into a production-grade compiler.

Tasks:

- Add `LLMContextSource`, `LLMContextInclusionMode`, `LLMContextCompileOptions`, `LLMContextSnapshot`, `LLMContextQualitySignal`, and `LLMCompactionPreview`.
- Implement optional-source degradation before removal.
- Track omitted sources and reasons.
- Support lossless per-request transforms separately from persisted lossy compaction.
- Add bounded-concurrency map/reduce for independent chunks, preserving output order.

Verification:

- Deterministic tests for inclusion modes, budgets, optional source shrink, omitted-source reasons, and cancellation.
- Performance micro-benchmarks only after the API shape settles.

### Phase 4: Model Endpoint Registry and Routing Policy

Goal: prepare for on-device, PCC, external cloud, local server, and future Foundation Models providers.

Tasks:

- Add `LLMModelEndpointDescriptor`.
- Add locality, cost class, health, quota, capability profile, max context, max output, routing preferences, and disallowed use cases.
- Add `LLMRoutingIntent` and route scoring.
- Update `LLMRouter` to explain why it selected or rejected clients.
- Add provider-neutral quota status without depending on iOS 27 symbols.

Verification:

- Router tests for hard requirements, soft preferences, quota rejection, locality preference, and fallback explanation.

### Phase 5: WWDC26 Foundation Models Support

Goal: make the Foundation Models adapter ready when the iOS 27 SDK is installed.

Pre-SDK tasks:

- Add provider-neutral types for `LLMReasoningEffort`, `LLMQuotaStatus`, `LLMLocality.privateCloudCompute`, and dynamic context size.
- Update docs to avoid hard-coding 4,096 tokens as the only Foundation Models limit.
- Add tests using fake Foundation clients.

Post-SDK tasks:

- Add `PrivateCloudComputeLanguageModel` support behind availability checks.
- Query `contextSize` dynamically.
- Map Apple quota states into `LLMQuotaStatus`.
- Map reasoning levels where supported.
- Add app-controlled quota-limit fallbacks.
- Add DocC snippets showing on-device, PCC, and fallback routing.
- Investigate adapters for `LanguageModel` or `LanguageModelExecutor` if SwiftLLM should expose Foundation Models provider bridges.

Verification:

- SDK-gated tests with fake and live-availability-safe paths.
- Showcase sample that can switch on-device/PCC with availability and quota handling.

### Phase 6: Evaluation Alignment

Goal: keep SwiftLLM's evaluation package useful now and compatible with Apple's new evaluation tooling later.

Tasks:

- Add workflow evaluation reports.
- Add comparative evaluation between endpoints.
- Add exported JSON that includes prompt version, model endpoint, context snapshot, receipts, assertions, and verdicts.
- Add model-as-judge hooks behind explicit provider configuration.
- Add docs for eval-driven prompt iteration.

Verification:

- Evaluation report fixture tests.
- At least one regression test for context compaction quality.

### Phase 7: Open Source Release Polish

Goal: publish with a credible first impression.

Tasks:

- Replace `LICENSE.md`.
- Replace `SECURITY.md` with public reporting instructions and supported versions.
- Expand `README.md` into a real public landing document with install, quick start, provider setup boundaries, on-device first example, external provider examples, evaluation example, privacy model, and roadmap.
- Add DocC coverage for each product.
- Add issue templates for provider bugs, Foundation Models availability, docs, and eval failures if needed.
- Add CI matrix if practical, at least build/test plus warnings-as-errors.
- Audit public symbol docs and API stability.
- Tag `0.1.0`.

License recommendation:

- Use Apache-2.0 if the project wants explicit patent protection, stronger enterprise comfort, and clearer contribution posture.
- Use MIT if the project wants maximum Swift package familiarity and the lightest possible terms.
- My recommendation is Apache-2.0 for SwiftLLM because it is a library that may sit near model adapters, provider behavior, and application infrastructure. If compatibility with MIT-derived snippets or contributor expectations becomes more important, MIT is also reasonable. The current placeholder must be replaced before public release either way.

## Swift 6.2 and Swift 6.3 Polish

SwiftLLM is already in good shape for strict concurrency:

- Public protocols and structs are broadly `Sendable`.
- Closure storage uses `@Sendable`.
- No broad `@MainActor` usage appears in source.
- No `@unchecked Sendable`, `@preconcurrency`, or unsafe concurrency escape hatches were found.
- Async streams cancel their worker tasks on termination.

Recommended next steps:

- Keep library code non-main-actor by default. Swift 6.2 default main actor isolation is useful for apps and scripts, but it is the wrong default for this package's core library target.
- Consider adding explicit Swift settings only after testing with the installed toolchain. Do not enable upcoming features blindly in a public package.
- Use warnings-as-errors in CI once the current SDK/toolchain baseline is clean.
- Add bounded task-group concurrency for map/reduce and retrieval fan-out where work is independent.
- Factor the repeated `AsyncThrowingStream` bridge pattern into a small helper only if it reduces duplication without hiding provider-specific stream state.
- Prefer actors or value-state pipelines for shared mutable state. Avoid locks unless a measured hot path requires one.
- Watch Swift 6.3 diagnostics around `@Sendable` and escaping closures before adopting new compiler settings broadly.

## Specific API Ideas

These names are placeholders for design discussion, not final API commitments.

```swift
public enum LLMLocality: Sendable, Hashable {
  case onDevice
  case privateCloudCompute
  case externalCloud
  case localServer
}

public enum LLMReasoningEffort: Sendable, Hashable {
  case automatic
  case low
  case medium
  case high
}

public struct LLMQuotaStatus: Sendable, Hashable {
  public var availability: Availability
  public var resetHint: String?
  public var limitIncreaseSuggestionAvailable: Bool

  public enum Availability: Sendable, Hashable {
    case available
    case approachingLimit
    case limitReached
    case unknown
  }
}

public struct LLMModelEndpointDescriptor: Sendable, Identifiable {
  public var id: String
  public var provider: String
  public var model: String
  public var locality: LLMLocality
  public var capabilities: LLMClientCapabilities
  public var maxContextTokens: Int?
  public var maxOutputTokens: Int?
  public var quota: LLMQuotaStatus?
  public var health: LLMEndpointHealth
}
```

```swift
public struct LLMContextCompileOptions: Sendable, Hashable {
  public var budget: TokenBudget
  public var allowedTrustLevels: Set<LLMContextTrustLevel>
  public var allowSensitiveSources: Bool
  public var preferLosslessTransforms: Bool
  public var preserveRequiredSources: Bool
}

public struct LLMContextSnapshot: Sendable, Identifiable {
  public var id: UUID
  public var sections: [LLMCompiledContextSection]
  public var tokenEstimate: Int
  public var omittedSources: [LLMOmittedContextSource]
  public var qualitySignals: [LLMContextQualitySignal]
}
```

## Near-Term Implementation Order

The highest-leverage first slice is:

1. Run baseline verification and record results.
2. Split large files without public API changes.
3. Add diagnostics/run receipt primitives.
4. Add context compiler v2.
5. Add endpoint registry and routing explanations.
6. Update Foundation Models docs/types for OS 27 readiness without importing unavailable SDK symbols.
7. Update README, license, security policy, and DocC.

This order keeps risk low. It improves developer ergonomics immediately, then adds the primitives needed for PCC and better cloud routing.

## Open Questions

- Should SwiftLLM keep iOS/macOS/visionOS 26 as the package minimum while adding iOS 27-only support behind availability, or should the next release raise platform minimums?
- Should PCC live inside `SwiftLLMFoundationModels` only, or should there be a separate product for Apple cloud features? I lean toward the same target because Apple exposes PCC through Foundation Models.
- Should model endpoint descriptors be stored by the app, or should SwiftLLM provide an in-memory registry only? I lean in-memory only. Persistence is app policy.
- Should comparative evaluation use external model judges by default? I lean no. It should be explicit because of privacy and cost.
- Which license posture matters more for the first public release: maximum familiarity (MIT) or explicit patent grant and enterprise clarity (Apache-2.0)?

## Risks

- iOS 27 and Xcode 27 APIs are beta-era and may change. SDK-gated code should wait until the local SDK is installed.
- PCC entitlement and program eligibility are product/distribution concerns, not just technical switches.
- "No cloud API cost" does not mean unlimited usage. Quota handling must be built into routing and UI hooks.
- Full prompt traces and debug bundles can contain sensitive data. Redaction should stay default.
- Lumen concepts are product-rich. SwiftLLM should take the library primitives, not the cockpit workflow.

## Decision Recommendation

Proceed with a polish-first, primitives-second path:

1. Keep the current architecture.
2. Organize large files and tests.
3. Add receipts and context snapshots.
4. Add model endpoint descriptors and routing explanations.
5. Prepare Foundation Models types and docs for PCC, reasoning, quota, dynamic context size, and Evaluations.
6. Replace public release placeholders and publish with Apache-2.0 unless there is a strong ecosystem reason to choose MIT.
