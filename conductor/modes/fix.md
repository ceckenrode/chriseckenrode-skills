# Fix supplied findings

Use this mode when the user supplies review findings or when an accepted
review-to-fix handoff authorizes a fix batch. This mode does not start a fresh
review. A later review or review loop requires an explicit user request.

## Triage and scope

1. Read the supplied findings and the current handoff when one exists. If no
   handoff exists, establish the scope, baseline, and required evidence from the
   supplied material; do not invent missing product requirements.
2. Read the [finding schema](review.md#finding-schema) and normalize each finding
   against it. Deduplicate findings. For uncertain items, seek targeted evidence
   first; then reject or defer unsupported findings with a recorded reason, and
   return `NEEDS_DECISION` only when ambiguity changes behavior or scope.
3. For plan-review findings, limit writes to the plan and handoff artifacts and
   verify that implementation remains gated by the corrected plan. When a
   finding changes architecture, route the correction to the selected planning
   owner/worker; the lead steers scope and accepts the result. Product-code
   findings retain their assigned write ownership and off-limits paths.

## Fix and verify

1. Confirm or reproduce each accepted finding where practical, then assign
   independent findings to disjoint fixers within the configured cap. Give each
   fixer the finding ID, exact ownership, expected behavior, and affected gates.
2. Apply the smallest authorized correction. For meaningful production behavior,
   preserve a failing regression check before the fix and a passing check after it.
   Documentation/configuration fixes receive appropriate direct checks. When
   shared contracts or multiple workers are affected, the explicit integration
   owner runs combined-state checks; individual green checks are not integration
   evidence.
3. Re-read every original finding and verify its trigger, changed paths, commands,
   results, and evidence-backed resolution. Run integration checks when shared
   behavior changed. A failed, skipped, or unavailable required gate remains
   unresolved and blocks completion or dependent work.

Record accepted, rejected, deferred, and resolved findings in the handoff, including
reasons for rejection or deferral. A cap-limited final fix may be verified, but it is
not independently re-reviewed. End with `DONE` only when every accepted finding is
resolved and every required gate passes; otherwise report the blocker or unverified
gate, and use `NEEDS_DECISION` or `NOT FOUND` as applicable.
