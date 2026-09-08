# Execution

1. Establish the accepted brief or plan. For a direct task, derive the brief
   from the requested scope, behavior, constraints, and acceptance criteria; no
   plan file or incoming handoff is required. For a supplied chat/file plan,
   check design, dependencies, ownership, acceptance criteria, and gates before
   coding; resolve missing prerequisites before dependents start. In either
   entry, confirm configured role settings and do not infer missing models or
   reasoning effort.
2. Dispatch ready work concurrently using the scheduler below. Give each worker
   the accepted brief or relevant plan section, binding interfaces and behavior,
   exact gates, and expected evidence. Workers return `NEEDS_DECISION` for
   consequential ambiguities or proposed deviations; resolve them before work
   proceeds.
3. Have implementers complete each planned tracer-bullet slice end-to-end:
   require its observable outcome, exact write ownership/off-limits scope, and
   selected gates. For meaningful behavior changes, require same-task observed
   red → implementation → green evidence where applicable. Each slice must leave
   a working state before its dependents release.
4. Apply the dispatch reference's active-supervision guidance throughout implementation. Compare checkpoint evidence with the planned design and quality bar, resolve blocked work and conflicts, and give workers precise corrective instructions before errors spread to dependent tasks.
5. Have implementers integrate completed slices, check scope, and verify affected
   behavior with documented project checks. Assess evidence; assign fixes for
   introduced failures and rerun affected checks. Use the slice contract in
   [planning](plan.md) to reject horizontal splits presented as end-to-end work.
   For docs/config-only work, use proportionate checks; do not require
   production TDD or artificial full-stack tests.

## Ready-task scheduler

Track each task as pending, ready, running, blocked, or verified. A task is ready when its prerequisite gates have passed, required decisions/artifacts exist, and its write scope and shared resources are available.

Fill available worker slots with independent ready tasks, respecting user-requested concurrency. When a task's gate passes, immediately release eligible dependents and dispatch more ready work; avoid waiting for an entire wave when only one prerequisite matters. Sequence genuinely coupled work and serialize or isolate shared build/test resources.

If a prerequisite fails or changes its contract, block its affected dependents, reassess any work based on the old contract, and keep unrelated tasks moving. Record graph changes and their reasons. Distinguish a runtime worker limit from a task dependency rather than inventing blockers to justify serial execution.

## Verification gates

- **Task gate:** require the worker's changed paths, acceptance-criteria results, exact commands and exit/results, and concise supporting evidence. The orchestrator accepts the implementation against the binding design and quality bar as well as test results. A `DONE` label alone does not release dependent work.
- **Integration gate:** after changes are combined, run the accepted brief or plan's project checks and checks for cross-task behavior against the combined state. Individual task passes do not establish integration success.
- **Acceptance gate:** verify the requested observable outcome. Where applicable, distinguish mocked tests from a real browser, application, provider, or deployment check; use the evidence the accepted brief or plan requires.

A failed, skipped, or unavailable required gate stays unresolved. Assign fixes and rerun affected gates; hold dependent work and completion until they pass. Independent work may continue. If evidence shows a gate is unsuitable, explicitly revise the accepted brief or plan with a reason rather than silently dropping it or weakening its assertion. A user-approved deferral is reported as unverified, never as passed.

Execution is complete when accepted scope is implemented, every required gate passes, and deviations are accounted for. Otherwise report the blocker and unverified behavior. No automatic reviewer is part of execution; requested review follows the main workflow's routing.

Write the execution-to-review, execution-to-final-verification, or execution-to-report handoff with task/gate outcomes, decisions, and remaining blockers. The next selected stage reads it before work; do not skip selected code review. Final verification follows the last authorized fix and does not add a review round. Report what changed, verification, limitations, and artifact paths.
