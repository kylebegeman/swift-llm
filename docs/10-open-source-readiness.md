# Open Source Readiness

## Current Status

SwiftLLM is ready for a local `1.0.0` release tag after the final validation script passes.

The repository is structured as a public Swift package:

- clear package targets
- durable docs
- agent docs
- contribution guide
- security policy
- Apache-2.0 license
- changelog
- CI validation workflow
- issue and pull request templates
- ignored generated Xcode projects
- example app generated from XcodeGen
- public-facing README

## Completed For 1.0.0

- choose and install Apache-2.0
- replace the initial `SECURITY.md` reporting stub with a GitHub Security Advisory path
- expand `README.md` with badges, diagrams, examples, provider boundaries, and WWDC26 readiness
- update `CONTRIBUTING.md` with public contribution rules
- add `docs/14-wwdc26-readiness.md`
- update roadmap status for public prep
- audit durable docs and examples for private Chime In data
- add release-ready diagnostics, endpoint routing, context compiler, and Foundation Models pre-SDK readiness docs
- split large source files into feature-focused modules
- add provider cached-input and reasoning-token telemetry
- add bounded parallel map-reduce execution for chunk pipelines
- build DocC documentation locally
- run clean package resolution from a separate sample app

## Post-Release Follow-Ups

- verify the tag and generated documentation after pushing to GitHub
- harden CI against additional supported Xcode versions as they become available
- add a showcase screenshot or short demo video after the UI grows beyond the shell
- expand DocC examples over time

## API Stability

SwiftLLM follows semantic versioning from `1.0.0` onward. Source-breaking changes should be reserved for major versions unless a security or platform compatibility issue leaves no practical alternative.

## Naming

Package name: `swift-llm`

Public product names:

- `SwiftLLM`
- `SwiftLLMFoundationModels`
- `SwiftLLMOpenAI`
- `SwiftLLMAnthropic`
- `SwiftLLMEvaluation`

Future product names should stay short and explicit.

## Public Positioning

Likely one-line description:

> SwiftLLM is a Swift-native reliability layer for local-first language model features on Apple platforms.

Avoid implying:

- it trains a new model
- it bypasses Apple limits
- it guarantees hallucination-free output
- it replaces evaluation
- it makes offline models equivalent to frontier cloud systems
- Private Cloud Compute has unlimited usage
- privacy guarantees apply equally to every provider adapter

## Community Contribution

The best public contribution would be a practical, boring toolkit that helps Apple developers ship on-device AI without each team rebuilding the same reliability layer.

The highest-value areas are:

- token-aware context management
- local RAG value types and packing
- guided generation validation
- prompt/version evaluation
- safety/fallback diagnostics

These are the parts most examples skip and most production apps need.

## License Rationale

Apache-2.0 is the recommended first public license because SwiftLLM is infrastructure-adjacent library code. The explicit patent grant and contribution terms are useful for app teams and companies evaluating adoption.

MIT would also be reasonable if maximum familiarity is more important than the patent grant. Any future license change must update `README.md`, `LICENSE.md`, package metadata, and release notes together.
