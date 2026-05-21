# Evaluate Prompt Change

## Use When

Use this playbook when changing prompt contracts, examples, validators, schemas, repair, fallback, or output quality expectations.

## Steps

1. Identify the prompt contract and version affected.
2. Add or update evaluation cases for the behavior being changed.
3. Include at least one negative case for common false positives.
4. Add `TextEvaluationAssertion` or `StructuredEvaluationAssertion` coverage for the expected behavior.
5. Generate or update a `PromptVersionEvaluationReport` when comparing prompt versions.
6. Keep report outputs redacted unless raw output capture is explicitly needed for local debugging.
7. Run `swift test`.
8. If the change affects Chime In behavior, add or update Chime In's domain evaluation/integration coverage too.
9. Update docs when prompt behavior or product guarantees change.

## What To Track

- required output signals
- forbidden output signals
- fallback reason
- validation failures
- token usage
- OS/model version when available
- prompt version

## Common Failures

- Improving one example while regressing another mode.
- Adding examples that blow the context budget.
- Treating model output quality as stable across OS releases.

## Read Next

- `../../docs/07-evaluation-and-diagnostics.md`
- `../capabilities/reliability-patterns.md`
