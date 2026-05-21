# Reliability Patterns

## The Pattern

Production AI systems improve reliability by surrounding models with deterministic systems:

```text
user/app input
  -> classify the task
  -> retrieve only relevant context
  -> compile a prompt contract
  -> budget tokens
  -> call the model with schema/tools
  -> validate and ground output
  -> repair or retry when useful
  -> fall back deterministically when needed
  -> record metadata and evaluate over time
```

SwiftLLM should adapt that pattern to Apple-native, offline workflows.

## Narrow Tasks

The on-device model should receive one clear job at a time.

Good:

- "Extract action items from this transcript."
- "Summarize this chunk in two sentences."
- "Classify whether this note contains a follow-up."

Bad:

- "Analyze this entire meeting and make a complete project plan with timelines."
- "Act as a general personal assistant."
- "Figure out everything important."

Narrow tasks reduce latency, context usage, hallucination, and refusal risk.

## Prompt Contracts

A prompt contract should include:

- stable ID
- version
- trusted instructions
- response schema description
- expected behavior boundaries
- example selection rules
- evaluation corpus references

The contract is more important than an ad hoc prompt string. It gives teams something to version, test, and debug.

## Few-Shot Examples

Examples help define style and edge behavior, but they are expensive.

SwiftLLM should support compact example selection:

- use only examples relevant to the current task
- prefer negative examples for common false positives
- cap example count
- keep example outputs short
- do not include examples if the schema and instructions are enough

Chime In already has this shape in its extraction example corpus. SwiftLLM should generalize the selection mechanism, not the Chime-specific examples.

## Retrieval Before Generation

When the model needs app data, the app should retrieve relevant snippets before generation whenever possible.

This avoids asking the model to choose from too many tools and keeps the context window predictable.

Good local sources:

- SQLite FTS
- recent notes
- selected transcript segments
- user-approved documents
- app state summaries
- deterministic search results

## Validation After Generation

Every model-backed output that affects product state should be validated.

Validation can check:

- required fields
- maximum counts
- enum values
- date parseability
- evidence spans
- source grounding
- duplicate items
- out-of-scope content
- unsafe output
- app-specific constraints

Validation should normalize the candidate into an app-owned draft. The model output is not the final product state.

The first structured generation toolkit now models this path explicitly:

```text
GenerationCandidate<Output>
  -> StructuredGenerationCandidate<Output>
  -> StructuredGenerationValidator<Output>
  -> StructuredGenerationRepairPolicy
  -> StructuredGenerationFallbackPolicy
  -> StructuredGenerationPipelineResult<Output>
```

Apps still own their final domain drafts. SwiftLLM owns the generic candidate, evidence, validation, repair, and fallback machinery.

## Grounding

Grounding means generated claims should be supported by the source context.

SwiftLLM should support simple deterministic grounding first:

- exact phrase containment
- content-word overlap
- source span preservation
- evidence fields in generated schemas
- per-item rejection

Later versions can add more advanced semantic grounding, but the first version should stay explainable.

## Repair and Retry

Retries are useful only when they are targeted.

Useful retry patterns:

- smaller schema
- fewer requested fields
- lower maximum output count
- shorter input chunk
- stricter prompt
- string refusal explanation after guided generation refusal

Bad retry patterns:

- repeat the same prompt three times
- raise temperature to "get something"
- discard validation failures silently

## Fallbacks

Fallbacks should be part of the design, not an error catch-all.

Common fallback reasons:

- model unavailable
- unsupported locale
- context exceeded
- guardrail violation
- refusal
- validation failure
- provider error

Fallback outputs may be:

- deterministic heuristic extraction
- partial structured draft
- empty result with clear metadata
- "needs review" state
- local search result with no model summary

## Human Verification

For workflows like Chime In, generated output should enter an editable verification surface before export.

This is especially important for:

- tasks
- calendar dates
- reminders
- decisions
- summaries that might be shared

SwiftLLM should make it easy to preserve provenance and validation reasons so the app can show appropriate review UI.
