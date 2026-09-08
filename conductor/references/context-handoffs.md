# Context and handoffs

## Locations

Create one task-specific temporary folder per run using the platform's temporary-directory helper, such as `mktemp -d "${TMPDIR:-/tmp}/conductor.XXXXXX"`. Record its absolute path and reuse it across stages and review rounds. Keep the ledger (`ledger.md`), briefs, handoffs, evidence summaries, and scratch prototypes there. Resume a supplied run folder when it still exists; temporary artifacts may not survive cleanup.

Keep `ledger.md` current after each synthesis: goal, decisions, ownership/status,
evidence, gates, and unresolved questions. Re-read it after resume or context
compaction before dispatch.

For automatic internal exploration, use the shared [exploration contract](exploration.md)
for selection, scope, and stopping. Exploration remains read-only and is evidence for
planning; it does not settle or bypass settings for implementation, review,
fixes, or a requested independent verifier.

For plans, use this order:

1. The location explicitly requested for this task, or an existing plan supplied for execution.
2. The user's established plan location, evidenced by the conversation, project instructions, or their existing plan files. Delegate a focused lookup if needed; preserve naming conventions and avoid overwriting an unrelated plan.
3. `<run-folder>/plan.md` when no established location is known.

Save a plan artifact when plan production is selected so downstream workers have
a stable reference. A supplied chat plan is already the plan and needs no
replacement file. Keep handoffs in the temporary folder when a stage boundary
exists; a fresh direct task needs only its bounded brief and run notes. Report
created plan, handoff, and run-folder paths when present.

## Write at boundaries

Before moving between planning, execution, review, fixes, or the final report, write a concise handoff for the completed stage. In review loops, write round-numbered review-to-fix and fix-to-review handoffs; record a final round's result even when it ends cleanly. A plan-only run also leaves a handoff for later execution. Name handoffs by stage so a resumed run can find them, for example `<run-folder>/handoffs/plan-to-execute.md` and `<run-folder>/handoffs/review-round-1-to-fix.md`; keep briefs in `<run-folder>/briefs/`.

Each handoff contains:

- Goal, exact constraints still in force, plan path when present, and current stage/round.
- Decisions and rationale, accepted deviations, and unresolved questions.
- Task IDs, ownership, status, dependency/gate state, and which work is ready next.
- Changed paths and relevant evidence/prototype paths; verification performed, results, and remaining gates.
- For reviews: reviewed baseline/state, reviewer IDs/models, accepted/rejected/fixed/deferred findings, and remaining round allowance.
- The agreed workflow configuration: selected sequence; included role owner,
  model, effort, separate caps, round limits/overrides, checkpoints, and final
  verification. Later user changes resolve affected settings before dispatch;
  settled choices are preserved.
- The next action, its prerequisites, and the worker/session IDs useful for resumption.

When exploration contributed evidence, also record the focused questions or areas,
explorer worker/session IDs, selected explorer model/effort, report paths, anchored
findings, uncertainties or `NOT FOUND` search scope, and the lead's sufficiency/stop
decision. Ensure the gathered evidence is usable for the requested answer or plan.
Reuse the report contract in [agent dispatch](agent-dispatch.md) and the policy in
[exploration](exploration.md); do not copy raw logs or repeat its policy.

Reference plans and evidence instead of duplicating their contents. Include enough context to explain intentional choices and prevent the next worker from rediscovering settled facts. The orchestrator authors the handoff from distilled reports; no external skill is needed.

## Read before work

At each stage entry or review round, the orchestrator reads the latest relevant
handoff when one exists and reconciles it with current task state. Every
downstream brief identifies the handoff and relevant plan sections when present;
fresh direct execution uses its accepted brief. Initial investigation uses the
intake brief until the first stage handoff exists. If an expected path is missing
or stale, reconstruct the needed context from the plan and current evidence
before dependent work proceeds.

A boundary is complete when its handoff exists, accounts for the stage's results and open work, and is included in the next assignment. Leave final artifacts available and report their paths; describe remaining work accurately rather than marking an interrupted run complete.
