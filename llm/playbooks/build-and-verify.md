# Build And Verify

## Use When

Use this playbook when building, testing, or checking the showcase.

## Commands

```sh
swift build
swift test
xcodegen generate --spec Examples/LLMShowcase/project.yml
```

`swift test` exercises the Foundation Models adapter through fakeable closures, so it does not require the Foundation Models framework to be present locally.

Open the generated showcase manually when UI changes matter:

```sh
open Examples/LLMShowcase/LLMShowcase.xcodeproj
```

## Generated Files

Generated `.xcodeproj` files are ignored and should not be committed.

## Common Failures

- XcodeGen is not installed.
- The active Xcode toolchain does not include the required 26 SDKs.
- Foundation Models APIs changed in a new SDK.

## Read Next

- `../capabilities/repo-map.md`
- `../../docs/10-open-source-readiness.md`
