---
name: conductor
description: Coordinate selected models across planning, implementation, and optional review workflows.
disable-model-invocation: true
---

# Conductor

Activate only on an explicit user request. For help or a bare invocation, read
[usage help](references/help.md) and stop without dispatching or writing artifacts.

The lead owns scope, steering, integration, and acceptance. Planning defaults to
the lead; an explicitly selected planner owns architecture and plan synthesis
within that scope. Implementers follow the settled design.

## Route by intent

| Intent | Read when entering the stage |
| --- | --- |
| Create a plan | [Planning](modes/plan.md) |
| Implement a task, fix a bug, or execute a supplied plan | [Execution](modes/execute.md) |
| Review a scope, with fixes or a loop if requested | [Review](modes/review.md) |
| Fix supplied review findings | [Finding fixes](modes/fix.md) |

Run only selected stages. Reviews and independent verifiers are opt-in;
execution includes its own verification. A direct task needs no plan artifact.

## Run

1. **Configure.** Read [workflow setup](references/workflow.md). Establish scope,
   acceptance criteria, and the complete selected workflow before dispatch.
   Finish when every selected role, gate, and stopping rule is settled.
2. **Brief.** Read [agent dispatch](references/agent-dispatch.md) and
   [context and handoffs](references/context-handoffs.md). Use the host's native
   subagents when available. Otherwise, use the CLI skill for the selected
   backend. Each worker needs bounded ownership, relevant context, and a
   checkable deliverable before it starts.
3. **Steer.** Follow the current stage's linked instructions. Release dependent
   work only after its prerequisite gates pass. Resolve drift through concrete
   corrections and evidence; a worker's `DONE` claim is not acceptance.
4. **Close.** Complete the selected stage's gates and handoff before advancing.
   At the final stage, report changed paths, check results, unresolved items,
   limitations, and artifact paths. An unavailable required gate remains open.

## Git boundary

Before edits, record pre-existing dirty paths with a read-only Git status check
and preserve unrelated work. Stage, commit, amend, tag, or push only when the
user explicitly requests that action; carry this boundary into worker briefs.
