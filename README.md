# SwiftLLM

SwiftLLM is a Swift package for making Apple-native language model features more reliable across on-device and explicitly configured provider-backed workflows.

It is not an attempt to make Apple Foundation Models behave like frontier cloud models. It focuses on the orchestration layer that production AI systems need even when the model is small and local:

- prompt contracts and versioning
- token budgeting and context packing
- chunked long-input pipelines
- transcript-aware map/reduce workflows
- structured generation validation
- evidence-aware candidate pipelines
- source-aware local retrieval-augmented generation pipelines
- typed workflow orchestration for deterministic analysis, retrieval, generation, validation, and fallback
- capability-aware routing and deterministic fallbacks
- prompt-version evaluation and redacted local diagnostics
- local-only run metadata and diagnostics

The package is private while it is incubated inside Chime In, but it is structured to become an open-source Swift package later.

## Products

| Product | Purpose |
|---|---|
| `SwiftLLM` | Core client, prompt, context, fallback, validation, retrieval, router, and metadata primitives |
| `SwiftLLMFoundationModels` | Apple Foundation Models availability, token counting, prewarming, typed generation, native tools, and error normalization |
| `SwiftLLMOpenAI` | OpenAI Responses API adapter with injectable response and streaming transport |
| `SwiftLLMAnthropic` | Anthropic Messages API adapter with injectable response and streaming transport |
| `SwiftLLMEvaluation` | Lightweight prompt regression and output assertion utilities |

## Provider-Neutral Usage

```swift
import SwiftLLM
import SwiftLLMAnthropic
import SwiftLLMFoundationModels
import SwiftLLMOpenAI

let local = AnyLLMClient(FoundationModelClient.live)
let openAI = AnyLLMClient.openAI(apiKey: openAIKey, model: "your-openai-model")
let anthropic = AnyLLMClient.anthropic(apiKey: anthropicKey, model: "your-anthropic-model")

let client = LLMRouter(
  primary: local,
  fallbacks: [openAI, anthropic]
)

let response = try await client.respond(
  to: LLMRequest(
    instructions: "Summarize in one sentence.",
    messages: [.user("Long local note...")],
    parameters: LLMGenerationParameters(maxOutputTokens: 120)
  )
)
```

API keys are provided by the app at runtime. SwiftLLM does not define a key storage policy.

`LLMRouter` checks provider capabilities before dispatch, falls back only for retryable failures by default, and can continue streaming from a fallback provider when the primary fails before producing output.

Native Foundation Models `Tool` values stay on the typed `SwiftLLMFoundationModels` API. Provider-neutral requests intentionally reject local tool execution unless an app calls the Foundation-specific wrapper with concrete `[any Tool]` values.

## Workflow Orchestration

`LLMWorkflow` composes typed `LLMStep` values for app-owned AI workflows:

```swift
let workflow = LLMWorkflow(detectHints)
  .then(retrieveLocalContext)
  .then(buildPromptPlan)
  .then(generateStructuredCandidate)
  .then(validateGrounding)
  .then(repairOrFallback)
```

The workflow layer records provider metadata, token/context reports, validation issues, fallback
reasons, and source evidence. It does not choose tools autonomously or make hidden provider calls.

## Showcase

The repository includes an XcodeGen iOS showcase app:

```sh
xcodegen generate --spec Examples/LLMShowcase/project.yml
open Examples/LLMShowcase/LLMShowcase.xcodeproj
```

Generated `.xcodeproj` files are intentionally ignored.

## Local Verification

```sh
swift build
swift test
./scripts/validate.sh
```

`./scripts/validate.sh` also validates the agent manifest, regenerates the showcase project when XcodeGen is installed, and builds the showcase when `xcodebuild` is available.

## Documentation

Start with:

- [Docs Index](docs/README.md)
- [Overview](docs/00-overview.md)
- [Architecture](docs/01-architecture.md)
- [Foundation Models Reference](docs/02-foundation-models-reference.md)
- [Reliability Patterns](docs/03-reliability-patterns.md)
- [Context and Chunking](docs/04-context-and-chunking.md)
- [Structured Generation](docs/05-structured-generation.md)
- [Local RAG](docs/06-local-rag.md)
- [Evaluation and Diagnostics](docs/07-evaluation-and-diagnostics.md)
- [Chime In Incubation](docs/08-chime-in-incubation.md)
- [Roadmap](docs/09-roadmap.md)
- [Open Source Readiness](docs/10-open-source-readiness.md)
- [API Stability](docs/11-api-stability.md)
- [Release Process](docs/12-release-process.md)
- [Provider Adapters](docs/13-provider-adapters.md)

Agents should start at [llm/START_HERE.md](llm/START_HERE.md).

## Branching

This package follows the shared package branch model:

- `next` is the default integration branch for active work
- `master` is the stable release branch
- feature branches should branch from `next`
- public releases should be promoted from `master`
