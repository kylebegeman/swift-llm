# Open Source Readiness

## Current Status

SwiftLLM is pre-`1.0` and ready for a public `0.1.0` release candidate after final owner review.

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

## Before Publishing

Required:

- confirm the Apache-2.0 copyright holder text is correct
- confirm the GitHub Security Advisory path works after the repository is public
- harden CI against the final supported Xcode matrix
- expand DocC/API reference coverage
- add screenshots, diagrams, or a small demo video
- define final semantic versioning policy for `0.x`
- mark unstable APIs clearly
- run clean package resolution from a separate sample app
- tag `0.1.0`

Completed in the first public-readiness pass:

- choose and install Apache-2.0
- replace `SECURITY.md` reporting placeholder
- expand `README.md` with badges, diagrams, examples, provider boundaries, and WWDC26 readiness
- update `CONTRIBUTING.md` with public contribution rules
- add `docs/14-wwdc26-readiness.md`
- update roadmap status for public prep
- audit durable docs and examples for private Chime In data
- add release-ready diagnostics, endpoint routing, context compiler, and Foundation Models pre-SDK readiness docs

Still recommended:

- expand release validation beyond the current local script
- add a short public architecture graphic or generated social preview if desired
- add a showcase screenshot after the app has meaningful UI
- run clean package resolution from a separate sample app after the GitHub remote is public

## API Stability

Before `1.0`, prefer explicit instability:

- keep experimental APIs documented
- avoid source-breaking churn without changelog notes
- use names that describe behavior, not implementation trends
- avoid broad public protocols until multiple adopters prove the shape

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

MIT would also be reasonable if maximum familiarity is more important than the patent grant. If the license changes before `0.1.0`, update `README.md`, `LICENSE.md`, package metadata, and release notes together.
