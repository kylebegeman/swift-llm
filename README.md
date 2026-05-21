# SwiftLLM

SwiftLLM is a Swift package for making Apple-native, offline, on-device language model features more reliable.

It is not an attempt to make Apple Foundation Models behave like frontier cloud models. It focuses on the orchestration layer that production AI systems need even when the model is small and local:

- prompt contracts and versioning
- token budgeting and context packing
- chunked long-input pipelines
- transcript-aware map/reduce workflows
- structured generation validation
- evidence-aware candidate pipelines
- source-aware local retrieval-augmented generation pipelines
- deterministic fallbacks
- prompt-version evaluation and redacted local diagnostics
- local-only run metadata and diagnostics

The package is private while it is incubated inside Chime In, but it is structured to become an open-source Swift package later.

## Products

| Product | Purpose |
|---|---|
| `SwiftLLM` | Core prompt, context, fallback, validation, and metadata primitives |
| `SwiftLLMFoundationModels` | Apple Foundation Models availability, token counting, prewarming, generation, and error normalization |
| `SwiftLLMEvaluation` | Lightweight prompt regression and output assertion utilities |

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
xcodegen generate --spec Examples/LLMShowcase/project.yml
```

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

Agents should start at [llm/START_HERE.md](llm/START_HERE.md).

## Branching

This package follows the shared package branch model:

- `next` is the default integration branch for active work
- `master` is the stable release branch
- feature branches should branch from `next`
- public releases should be promoted from `master`
