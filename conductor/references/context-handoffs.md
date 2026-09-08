# Context and handoffs

## Locations

Create one task-specific temporary folder per run using the platform's temporary-directory helper, such as `mktemp -d "${TMPDIR:-/tmp}/conductor.XXXXXX"`. Record its absolute path and reuse it across stages and review rounds. Keep briefs, handoffs, evidence summaries, and scratch prototypes there. Resume a supplied run folder when it still exists; temporary artifacts may not survive cleanup.

For plans, use this order:

1. The location explicitly requested for this task, or an existing plan supplied for execution.
2. The user's established plan location, evidenced by the conversation, project instructions, or their existing plan files. Delegate a focused lookup if needed; preserve naming conventions and avoid overwriting an unrelated plan.
3. `<run-folder>/plan.md` when no established location is known.

Save even a short plan so downstream workers have a stable reference. Keep handoffs in the temporary folder regardless of the plan's location. Report the plan and run-folder paths so the user can resume the work.

## Write at boundaries

Before moving between planning, execution, review, fixes, or the final report, write a concise handoff for the completed stage. In review loops, write round-numbered review-to-fix and fix-to-review handoffs; record a final round's result even when it ends cleanly. A plan-only run also leaves a handoff for later execution.

Each handoff contains:

- Goal, exact constraints still in force, plan path, and current stage/round.
- Decisions and rationale, accepted deviations, and unresolved questions.
- Task IDs, ownership, status, dependency/gate state, and which work is ready next.
- Changed paths and relevant evidence/prototype paths; verification performed, results, and remaining gates.
- For reviews: reviewed baseline/state, reviewer IDs/models, accepted/rejected/fixed/deferred findings, and remaining round allowance.
- The next action, its prerequisites, and the worker/session IDs useful for resumption.

Reference plans and evidence instead of duplicating their contents. Include enough context to explain intentional choices and prevent the next worker from rediscovering settled facts. The orchestrator authors the handoff from distilled reports; no external skill is needed.

## Read before work

At each stage entry or review round, the orchestrator reads the latest relevant handoff and reconciles it with current task state. Every downstream brief identifies the handoff and relevant plan sections to read before acting. Initial investigation uses the intake brief until the first stage handoff exists. If an expected path is missing or stale, reconstruct the needed context from the plan and current evidence before dependent work proceeds.

A boundary is complete when its handoff exists, accounts for the stage's results and open work, and is included in the next assignment. Leave final artifacts available and report their paths; describe remaining work accurately rather than marking an interrupted run complete.
