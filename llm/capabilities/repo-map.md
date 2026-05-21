# Repo Map

## Use When

Use this card when deciding where a new API, test, doc, or showcase change belongs.

## Package Targets

| Target | Purpose |
|---|---|
| `SwiftLLM` | Core app-neutral primitives for prompts, context, validation, fallback, and metadata |
| `SwiftLLMFoundationModels` | Integration layer for Apple Foundation Models |
| `SwiftLLMEvaluation` | Prompt and output evaluation helpers |
| `SwiftLLMTests` | Unit tests for core behavior and evaluation primitives |

## Ownership Rules

- Put app-neutral value types in `SwiftLLM`.
- Put anything importing `FoundationModels` in `SwiftLLMFoundationModels`.
- Put test/eval harness utilities in `SwiftLLMEvaluation`.
- Put demo UI only in `Examples/LLMShowcase`.
- Put durable docs in `docs/`.
- Put compact agent docs in `llm/`.
- Put temporary notes in `scratch/`.

## Files Likely Involved

- `Package.swift`
- `Sources/SwiftLLM/Core/`
- `Sources/SwiftLLM/Prompting/`
- `Sources/SwiftLLM/Context/`
- `Sources/SwiftLLM/Retrieval/`
- `Sources/SwiftLLM/Validation/`
- `Sources/SwiftLLM/Generation/`
- `Sources/SwiftLLM/StructuredGeneration/`
- `Sources/SwiftLLMFoundationModels/`
- `Sources/SwiftLLMEvaluation/`

## Common Failure Modes

- Moving Chime In-specific concepts into the package too early.
- Importing Foundation Models in `SwiftLLM`.
- Adding a dependency to the core target before a real need appears.
- Updating package behavior without updating docs or evals.

## Read Next

- `../docs/01-architecture.md`
- `foundation-models-wrapper.md`
- `reliability-patterns.md`
