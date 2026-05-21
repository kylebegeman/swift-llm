# Open Source Readiness

## Current Status

SwiftLLM is private during incubation.

The repository is being structured as if it will become public later:

- clear package targets
- durable docs
- agent docs
- contribution guide
- security placeholder
- license placeholder
- changelog
- ignored generated Xcode projects
- example app generated from XcodeGen

## Before Publishing

Required:

- choose and install the final open-source license
- replace `SECURITY.md` reporting placeholder
- audit docs for private references
- audit examples for Chime In data
- add CI
- add release validation
- add DocC or API reference docs
- add screenshots or a small demo video
- define semantic versioning policy
- mark unstable APIs clearly

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

## Community Contribution

The best public contribution would be a practical, boring toolkit that helps Apple developers ship on-device AI without each team rebuilding the same reliability layer.

The highest-value areas are:

- token-aware context management
- local RAG value types and packing
- guided generation validation
- prompt/version evaluation
- safety/fallback diagnostics

These are the parts most examples skip and most production apps need.
