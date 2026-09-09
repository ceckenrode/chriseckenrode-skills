# Agent dispatch

## Backend

Honor an explicitly requested backend. Otherwise use the host's native subagents
when they can supply the selected worker; a model name alone does not request a
CLI. Inspect the exposed schema for model, effort, context inheritance, capacity,
and lifecycle controls. Keep follow-ups and result collection on that mechanism.

When native dispatch is unavailable or incompatible, use the model-invoked CLI
skill for the selected backend:

| Backend | Skill to load |
| --- | --- |
| Codex CLI | `use-codex` |
| Claude Code CLI | `use-claude` |
| GLM via OpenCode | `use-glm` |

Discover these by skill name in the host's installed catalog; in this source
repository each lives in its own top-level directory. Load only the selected
skill. It owns commands, authentication preflight, permissions flags, output
capture, and session reuse. If absent, report the missing skill and its repository
location; use the host's installation workflow when authorized. For another
backend, use its available dispatch skill or report the missing capability.
Announce a fallback and its reason once. Native slowness, task failure, or a
permission denial does not authorize switching backends to evade a restriction.

Preserve the model and effort settled in [workflow setup](workflow.md), including
on resume. A fallback never authorizes model substitution. When the installed
`spawn-glm` low-level wrapper is explicitly requested, load it as directed by
`use-glm`; its wrapper recipes remain there.

Workers use full permissions by default within host restrictions, unless the
user requests a restricted mode. Native workers inherit runtime permissions;
use only exposed controls. Read-only assignment scope still applies.

## Brief

Give workers enough outbound context to act without rediscovering the design;
request distilled inbound evidence. Use this contract:

```text
Objective: deliverable and purpose.
Context: project path, handoff, relevant plan sections, known file/type leads.
Scope: read-only or writable ownership, exclusions, and Git authorization.
Approach: ordered steps, settled design, binding interfaces/examples and rationale.
Acceptance: observable behavior or questions that must be answered.
Validation: checks, prerequisites, and what passing establishes.
Checkpoints: milestones for evidence or decisions before dependent work.
Report: result, changed paths, evidence, checks/results, and unresolved items.
```

For implementers, spell out boundary/error cases, lifecycle obligations, and
exact user-visible states that a weaker model might miss. Resolve consequential
design gaps before dispatch. Planning briefs instead delegate architecture to
the selected planner and require recorded rationale. Investigators and reviewers
are read-only; request file/line anchors, minimal excerpts, and uncertainties.

End reports with `DONE` plus evidence, `NEEDS_DECISION` plus the missing choice
and consequences, or `NOT FOUND` plus searched locations. Assess uncertainty and
evidence before releasing dependents.

## Supervision

Parallelize independent assignments within available slots; give writers
disjoint ownership. Name shared-contract and integration owners before consumers
start. The integration owner checks the combined state, beyond individual passes.

Track worker/session ID, backend, ownership, milestone, status, and result in the
ledger. Reuse workers for related follow-ups with the delta and failure evidence.
Use runtime event waits or bounded status checks while synthesizing other work.

For substantial assignments, set checkpoints at the first representative result,
before expensive dependent work, and at verification. Request artifacts, evidence,
next action, and blockers. A short bounded task may report only at completion.

Intervene on scope drift, guessed interfaces, repeated rediscovery, or unsupported
claims. Distinguish a long-running check from a stall. Send the mismatch, evidence,
required correction, and confirming gate. If correction fails, tighten the brief,
split work, or reassign within the user's model constraints. Retry only with new
information; hold dependents when context or capability remains unavailable.

For material uncertainty, inspect focused diffs or demonstrated behavior against
the brief. This acceptance work does not add an independent review stage.

On interruption or redirection, follow the recovery procedure in
[context and handoffs](context-handoffs.md#recovery).
