# Contributing

Thanks for helping improve SwiftLLM. This package is meant to stay small, app-neutral, local-first by default, and explicit about every provider boundary.

## Project Shape

SwiftLLM is split into focused products:

- `SwiftLLM`: core prompt, context, retrieval, validation, workflow, routing, and metadata primitives
- `SwiftLLMFoundationModels`: the only target that imports Apple's Foundation Models framework
- `SwiftLLMOpenAI`: OpenAI Responses API adapter
- `SwiftLLMAnthropic`: Anthropic Messages API adapter
- `SwiftLLMEvaluation`: prompt evaluation, report, and diagnostics utilities

Keep app-specific models, product workflows, UI, account state, and credential storage outside this package unless a durable design doc promotes a generic primitive into SwiftLLM.

## Local Setup

Requirements:

- Swift 6.2 or newer
- Xcode with iOS, macOS, and visionOS 26 SDKs
- XcodeGen for the optional showcase app

Useful commands:

```sh
swift build
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/validate.sh
```

`./scripts/validate.sh` validates the Swift package, agent manifest, and showcase project when local tools are available.

## Development Rules

- Keep `SwiftLLM` free of app-specific concepts.
- Keep `SwiftLLMFoundationModels` as the only target that imports `FoundationModels`.
- Keep provider HTTP translation inside provider adapter targets.
- Do not add API key persistence, token refresh, sign-in flows, or credential policy to the package. Apps own that boundary.
- Do not add telemetry or background network behavior.
- Do not add a production dependency without clear need and a design note.
- Do not commit generated `.xcodeproj` files, local build artifacts, credentials, `.env` values, transcripts with private data, provider payloads, or debug bundles.
- Add evaluation coverage when changing prompt contracts, validators, context packing, chunking, retrieval, fallback, or provider routing behavior.
- Preserve useful diagnostic context in errors, but do not leak secrets or raw private content by default.

## Swift And Concurrency

- Prefer Swift 6 style and strict data-race safety.
- Prefer value types, `Sendable`, structured concurrency, and cancellation-aware async code.
- Do not blanket library APIs with `@MainActor`.
- Avoid `Task.detached`, global mutable state, locks, and unsafe concurrency escape hatches unless there is a measured need and tests around the boundary.
- Keep streaming APIs cancellation-aware.
- Run warnings-as-errors before publishing API changes.

## Foundation Models And OS 27 Work

SwiftLLM currently targets the iOS, macOS, and visionOS 26 SDK era. OS 27 work should be added carefully:

- Keep source compiling on the currently supported SDK.
- Gate OS 27 APIs with availability checks and conditional compilation as needed.
- Represent new concepts in provider-neutral SwiftLLM types before importing new SDK symbols.
- Do not hard-code context windows when the platform can report `contextSize`.
- Treat Private Cloud Compute as networked model execution in policy and diagnostics.
- Add tests with fake clients before requiring live Apple Intelligence availability.

Relevant OS 27 concepts include Private Cloud Compute, reasoning levels, quota usage, Dynamic Profiles, `LanguageModel` provider packages, Core AI/MLX local language models, system tools, and the Evaluations framework.

## Documentation Rules

- Durable decisions belong in `docs/`.
- Agent routing belongs in `llm/`.
- Temporary notes belong in `scratch/`.
- Public-facing examples must use placeholder API keys and synthetic data.
- Keep privacy claims tied to implementation.
- When an idea graduates from `scratch/`, move the durable parts into `docs/` and remove or rewrite stale scratch notes.

## Pull Requests

Every PR should include:

- a short description of the developer or user problem
- the implementation approach
- tests or a clear reason tests do not apply
- documentation updates for architecture or API changes
- prompt or evaluation updates for generation behavior changes
- the verification command output or the exact local blocker

Before opening a PR, run the narrowest meaningful verification. For package-wide changes, run:

```sh
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/validate.sh
```

## Issue Types

Good issues include:

- API boundary problems
- Foundation Models availability or error-normalization gaps
- provider adapter decoding or streaming bugs
- context packing and token budgeting failures
- structured generation validation gaps
- evaluation or diagnostics improvements
- documentation mismatches

For security or privacy issues, use [SECURITY.md](SECURITY.md) instead of a public issue.

## Release Discipline

SwiftLLM follows semantic versioning from `1.0.0` onward. Source-breaking changes should be reserved for major versions unless a security or platform compatibility issue leaves no practical alternative.

Follow:

- [API Stability](docs/11-api-stability.md)
- [Release Process](docs/12-release-process.md)
- [Open Source Readiness](docs/10-open-source-readiness.md)
