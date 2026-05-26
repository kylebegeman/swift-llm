# API Stability

## Current Stability Level

SwiftLLM is pre-`1.0` and private during incubation.

The package should still behave like a serious public package now: source-breaking changes are allowed, but they must be intentional, documented, and covered by tests where behavior changes.

## Versioning Policy

Before public release:

- use `0.x` versions
- allow source-breaking changes between minor versions
- document breaking changes in `CHANGELOG.md`
- avoid breaking changes in patch versions
- prefer additive changes when the existing shape is already plausible

At `1.0`:

- follow semantic versioning
- reserve source-breaking changes for major versions
- keep deprecations around for at least one minor release when practical
- document migration steps for removed or renamed APIs

## Public API Categories

### Stable Candidates

These APIs are closest to public shape:

- provider metadata
- prompt contracts
- token budget and token counter
- simple chunking
- grounding validation
- fallback reasons
- evaluation result records

They are small value types and already have tests.

### Incubating APIs

These are useful but should remain easy to revise:

- Foundation Models generation wrappers
- provider-neutral client request/response types
- OpenAI and Anthropic adapters
- provider capabilities and router fallback policy
- router and high-level LLM pipeline
- structured generation pipeline
- workflow orchestration primitives (`LLMWorkflow`, `LLMStep`, `LLMWorkflowResult`, and workflow diagnostics)
- transcript chunking
- local RAG pipeline
- context packing strategies
- structured output assertions
- debug bundle format

They should become stable after Chime In exercises them in real workflows.

### Experimental Future APIs

These should not be promised publicly until implemented and tested:

- provider retry/backoff policy hooks
- Foundation Models tool-call wrappers
- SQLite/GRDB retrieval adapters
- embedding-backed retrieval
- automatic repair loops
- concurrent map/reduce execution
- custom Foundation Models adapter management

## Naming Rules

- Prefer behavior names over implementation trend names.
- Keep app-specific language out of public API names.
- Keep provider-specific names inside provider-specific targets.
- Do not use "magic", "agent", or "chain" terminology unless the API genuinely models that concept.
- Prefer "workflow" and "step" for deterministic app-composed orchestration. Reserve "agent" for a
  future API only if the package actually owns autonomous planning, tool choice, and execution loops.

## Deprecation Rules

When replacing a public API:

1. Add the new API.
2. Add tests for the new behavior.
3. Mark the old API deprecated when the migration is clear.
4. Document migration notes in `CHANGELOG.md`.
5. Remove the old API only at an allowed breaking-change boundary.

During private incubation, a direct replacement is acceptable if the change is documented in the changelog.

## Compatibility Checks

Before tagging a public release:

- run `./scripts/validate.sh`
- build DocC documentation
- scan `Sources/` for public symbols added without docs or tests
- scan docs for private Chime In details
- verify generated Xcode projects and build artifacts are not staged
