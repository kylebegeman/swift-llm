# Agent Routing

Read [`llm/START_HERE.md`](llm/START_HERE.md) before scanning source.

## Repository Rules

- Treat `docs/` as long-lived human documentation and product/architecture source of truth.
- Treat `llm/` as compact agent routing and operational guidance.
- Treat `scratch/` as expendable working notes. Do not cite scratch files as source of truth unless a durable doc links to them.
- Do not commit generated `.xcodeproj` files; regenerate them from `Examples/*/project.yml`.
- Keep package APIs app-neutral. Chime In may incubate requirements, but Chime-specific models belong in Chime In unless promoted into generic primitives.
- Keep privacy claims tied to implementation. The default package posture is local-first and offline-capable, not “magically private” for every adopter.

## Repo-Specific Routing Hints

- If the task is about target boundaries, public API placement, or package shape, read:
  - `llm/capabilities/repo-map.md`
  - `docs/01-architecture.md`
- If the task is about Foundation Models behavior, availability, guided generation, tools, context windows, or safety, read:
  - `llm/capabilities/foundation-models-wrapper.md`
  - `docs/02-foundation-models-reference.md`
  - `docs/03-reliability-patterns.md`
- If the task is about Chime In adoption, transcript extraction, or incubation scope, read:
  - `llm/capabilities/chime-in-incubation.md`
  - `docs/08-chime-in-incubation.md`
- If the task changes prompts, validation, or output quality expectations, update or add evaluation cases and read:
  - `llm/playbooks/evaluate-prompt-change.md`
  - `docs/07-evaluation-and-diagnostics.md`

Prefer docs-first exploration over broad source scans. Escalate to code after the relevant playbook or capability card points you at specific targets or files.
