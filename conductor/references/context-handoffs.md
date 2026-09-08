# Context and handoffs

## Locations

Create one task-specific temporary folder per run with the platform's temporary
folder helper. Record its absolute path; keep the ledger, briefs, handoffs,
evidence, and scratch prototypes there. Resume a supplied folder if it exists.
Temporary artifacts may be cleaned up, so report their paths at completion.

Update `ledger.md` after synthesis with the goal, accepted workflow configuration,
decisions, ownership/status, evidence, gates, and unresolved questions. Re-read it
after resume or compaction before dispatch.

Save a newly requested plan using this precedence:

1. The user's explicit path.
2. An established project plan location evidenced by instructions or existing files.
3. `<run-folder>/plan.md`.

Preserve existing naming conventions and unrelated plans. A supplied chat/file
plan is already usable; direct execution needs only a bounded brief and run notes.

## Stage boundaries

Write a handoff before advancing to the next stage or final report. A plan-only
run leaves one for later execution. Use stage names such as
`handoffs/plan-to-execute.md`; number review-to-fix and fix-to-review handoffs by
round, including the final clean round. Keep assignments in `briefs/`.

Each handoff records:

- Goal, active constraints, stage/round, and plan/evidence links.
- Decisions and rationale, accepted deviations, and unresolved questions.
- Task IDs, owners, status, dependency gates, and ready work.
- Changed paths, verification results, remaining gates, and limitations.
- Accepted workflow configuration and any explicit overrides.
- Next action, prerequisites, and useful worker/session IDs.

For reviews, also record the reviewed baseline, reviewer models/IDs, finding
IDs/dispositions, and remaining rounds. For exploration, record questions,
explorer models/effort/IDs, report paths, anchored findings, uncertainties or
searched scope, and the lead's sufficiency decision. Link evidence instead of
copying raw logs.

At stage entry, reconcile the relevant handoff with current artifacts. Include
that handoff and applicable plan sections in downstream briefs. A boundary is
complete when its handoff accounts for results and open work and reaches the
next assignment.

## Recovery

On interruption or redirection, stop affected workers, capture partial changes
and evidence, and mark checks tied to the old scope or contract stale. Preserve
unrelated progress. Reconcile the new brief before restarting affected work.

If the ledger or handoff is missing or stale, reconstruct state from the supplied
plan, actual partial work, and available evidence. Report gaps and hold dependent
work until its prerequisites are known. Configuration reuse follows
[workflow setup](workflow.md); recovery grants no new task or Git authorization.
