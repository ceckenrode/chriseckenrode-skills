---
name: conductor
description: User-invoked orchestration that keeps the lead's context available while it delegates bounded work, verifies results, and steers the requested workflow.
disable-model-invocation: true
---

# Conductor

## Invocation and ownership

Activate only when the user explicitly invokes Conductor through a skill mention,
`/conductor`, or an explicit request. Help and bare usage discover intent but do
not dispatch workers, write run artifacts, or start implementation.

The lead owns scope, architecture, decisions, synthesis, steering, and
acceptance. Workers receive bounded assignments and return evidence; they do not
invent product or workflow decisions. Conductor is self-contained and
host-agnostic: prefer native workers, and use a compatible CLI only when
requested or needed.

## Route by intent

Use intent, not a keyword in isolation:

| User intent | Branch |
|---|---|
| Help, bare invocation, or workflow question | [help](references/help.md); stop without work |
| Task/implement/fix an issue | [execution](modes/execute.md) |
| Explicitly create a plan | [planning](modes/plan.md) |
| Execute a supplied plan | [execution](modes/execute.md) |
| Review a scope or change | [review](modes/review.md) |
| Fix supplied review findings | [fix](modes/fix.md) |
| Explicit review/fix loop | [review](modes/review.md) |

An ordinary issue fix is execution, not supplied-findings triage. A complete
plan → optional plan review → implementation → optional code review → final
verification chain is an example, not an automatic pipeline; only requested
stages run. Reviews and independent verifiers are opt-in.

## Run

1. Identify the requested branch, scope, constraints, and acceptance criteria.
   Read [workflow setup](references/workflow.md). Settle the complete settings
   for selected user-configured roles; authorized read-only exploration may
   precede unresolved downstream settings under [exploration](references/exploration.md).
2. Read [context and handoffs](references/context-handoffs.md) and
   [agent dispatch](references/agent-dispatch.md). Restore supplied plans,
   findings, or handoffs when present; a fresh direct task needs only a bounded
   brief and run notes. Each assignment names ownership, scope, evidence, and a
   gate.
3. Read only the selected branch: [planning](modes/plan.md),
   [execution](modes/execute.md), [review](modes/review.md), or
   [supplied-findings fix](modes/fix.md). Direct implementation needs no saved
   plan or independent verifier; use execution's built-in checks. A supplied-
   findings fix does not launch a fresh review.
4. Monitor, synthesize, and steer. Advance only when acceptance criteria and
   required gates have checkable evidence; otherwise hold dependents and report
   the blocker. Preserve read-only scope where selected.
5. Complete the selected branch's verification, then report changed paths,
   checks/results, unresolved items, and limitations. Do not add an unrequested
   stage, verifier, review round, commit, staging, or push.

## Guardrails

Do not commit, stage, amend, tag, or push unless the user explicitly requests
that action. Before repository edits, when Git is available, inspect read-only
`git status --porcelain` and record pre-existing paths so unrelated dirty work is
preserved without needless reapproval. Keep run notes in the run folder and use concise handoffs at stage
boundaries. The lead accepts results from evidence, not a `DONE` label alone.
