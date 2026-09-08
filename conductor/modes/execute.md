# Execution

1. Read the incoming handoff and plan. Check that each task has the planning contract's design, acceptance criteria, dependencies, ownership, and verification gates. Restore the task graph and resolve missing design decisions and unavailable gate prerequisites before dependent work starts.
2. Dispatch ready tasks concurrently using the scheduler below. Give each worker the current handoff, relevant plan section, binding code/interfaces and behavior, exact gate commands, and expected evidence. Workers return `NEEDS_DECISION` for consequential ambiguities or proposed design deviations; you resolve them before affected work proceeds.
3. Have implementers follow project testing conventions. For behavior changes, request checks that distinguish correct from incorrect behavior and bug reproduction before fixes where practical. Match test effort to risk, and enforce all gates selected in the plan.
4. Apply the dispatch reference's active-supervision guidance throughout implementation. Compare checkpoint evidence with the planned design and quality bar, resolve blocked work and conflicts, and give workers precise corrective instructions before errors spread to dependent tasks.
5. Have implementers integrate the combined change, check task scope, and verify affected behavior with documented project checks. Assess their evidence; you may run verification commands directly. Assign fixes for introduced failures and rerun affected checks; broaden testing when new evidence warrants it.

## Ready-task scheduler

Track each task as pending, ready, running, blocked, or verified. A task is ready when its prerequisite gates have passed, required decisions/artifacts exist, and its write scope and shared resources are available.

Fill available worker slots with independent ready tasks, respecting user-requested concurrency. When a task's gate passes, immediately release eligible dependents and dispatch more ready work; avoid waiting for an entire wave when only one prerequisite matters. Sequence genuinely coupled work and serialize or isolate shared build/test resources.

If a prerequisite fails or changes its contract, block its affected dependents, reassess any work based on the old contract, and keep unrelated tasks moving. Record graph changes and their reasons. Distinguish a runtime worker limit from a task dependency rather than inventing blockers to justify serial execution.

## Verification gates

- **Task gate:** require the worker's changed paths, acceptance-criteria results, exact commands and exit/results, and concise supporting evidence. The orchestrator accepts the implementation against the binding design and quality bar as well as test results. A `DONE` label alone does not release dependent work.
- **Integration gate:** after changes are combined, run the plan's project checks and checks for cross-task behavior against the combined state. Individual task passes do not establish integration success.
- **Acceptance gate:** verify the requested observable outcome. Where applicable, distinguish mocked tests from a real browser, application, provider, or deployment check; use the evidence the plan requires.

A failed, skipped, or unavailable required gate stays unresolved. Assign fixes and rerun affected gates; hold dependent work and completion until they pass. Independent work may continue. If evidence shows a gate is unsuitable, explicitly revise the plan with a reason rather than silently dropping it or weakening its assertion. A user-approved deferral is reported as unverified, never as passed.

Execution is complete when accepted scope is implemented, every required gate passes, and deviations are accounted for. Otherwise report the blocker and unverified behavior. No automatic reviewer is part of execution; requested review follows the main workflow's routing.

Write the execution-to-review or execution-to-report handoff with task/gate outcomes, decisions, and remaining blockers. The next stage reads it before work. Report what changed, verification, limitations, and artifact paths.
