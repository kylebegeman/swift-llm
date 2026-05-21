# Contributing

SwiftLLM is private during incubation. These contribution rules are written now so the repository can be published with minimal policy churn later.

## Local Setup

Requirements:

- Swift 6.2 toolchain
- Xcode with iOS/macOS/visionOS 26 SDKs
- XcodeGen for the showcase app

Useful commands:

```sh
swift build
swift test
xcodegen generate --spec Examples/LLMShowcase/project.yml
```

## Development Rules

- Keep `SwiftLLM` free of app-specific concepts.
- Keep `SwiftLLMFoundationModels` as the only target that imports `FoundationModels`.
- Keep provider HTTP translation inside provider adapter targets.
- Do not add API key persistence or credential policy to the package; apps own that boundary.
- Add evaluation coverage when changing prompt contracts, validators, chunking, or fallback behavior.
- Do not add telemetry or new external-provider behavior without explicit design docs.
- Do not commit generated `.xcodeproj` files or local build artifacts.

## Documentation Rules

- Durable decisions belong in `docs/`.
- Agent routing belongs in `llm/`.
- Temporary notes belong in `scratch/`.
- When an idea graduates from `scratch/`, move the durable parts into `docs/` and delete or rewrite the scratch note.

## Pull Request Expectations

Before publishing publicly, every PR should include:

- a short description of the user/developer problem
- tests or a clear reason tests do not apply
- documentation updates for architecture or API changes
- prompt/evaluation updates for generation behavior changes
