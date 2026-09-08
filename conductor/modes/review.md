# Requested review

## Scope and dispatch

Read the incoming stage or previous-round handoff when one exists. Use the user's
files, diff, baseline, context, or plan. After execution, default to task-owned
changes; for standalone review, identify scope from supplied context and clarify
material ambiguity. If no handoff exists, establish a compact starting-state
handoff from the available scope and delegated diff summary; do not invent a plan.

Inventory the complete selected scope against its baseline before dispatch: staged,
unstaged, and untracked files; additions, deletions, and renames; generated files;
and touched tests and documentation. Do not broaden a task-owned review to unrelated
dirty work.

Honor specified and inherited models, effort, reviewer counts, lenses, and
format. Use the complete workflow configuration resolved up front; do not reset
per-stage overrides or a delegated planning owner to runtime defaults. Supply
the relevant plan contract, design rationale, binding examples/interfaces, review
scope, and gate evidence.

Use correctness, tests, simplicity, and project-rules as coverage lenses. They are
review questions, not mandatory reviewer slots; assign only the requested reviewer
count and keep independent lenses disjoint where practical.

For plan review, inspect assumptions and design, task dependencies, readiness
for implementation, and verification gates. Plan fixes update the plan and its
handoff; they do not edit product code. Findings that require an architectural
plan correction route to the selected planning owner/worker, while the lead
steers scope and accepts the corrected plan. Follow the selected plan-reviewer
and plan-fixer settings, which may differ from code-review settings.

Reviewer count, model selection, reasoning effort, and round count are independent
controls. Multiple reviewers may use the same model or different models and effort
levels. Do not infer a parallel count from a round count, or assume all roles share
one model. Multiple reviewers without a loop request still means one review round.

## Finding schema

Reviewers are read-only. Each finding uses a stable ID and contains severity
(`Critical`, `Important`, or `Minor`), location, issue, trigger/impact, evidence, and
a concrete correction. Request concrete defects introduced by the change; reject
speculative preferences. Check plan conformance, correctness, regressions, specified
edge cases, and whether verification demonstrates the claimed behavior. Validate
parent routes, middleware, shared contracts, and test-harness assumptions before
reporting an apparent omission in a child module. Code that matches a flawed plan
can still be defective; report the flaw and its impact so the orchestrator can revise
the decision. A no-findings report must still state verification limits.

## Findings and fixes

Deduplicate reports and adjudicate findings using the intended behavior and supporting evidence. Ask workers for targeted evidence when a claim needs clarification. Separate actionable defects from unsupported findings and optional preferences. A review-only request ends with the findings report.

If fixes are requested, send accepted findings with write ownership, explicit
corrective instructions, expected behavior, and affected verification gates to
[fix mode](fix.md). Require gate evidence after fixes, including integration checks
when shared behavior changed. Track each finding from its original ID through
disposition, changed paths, checks and results, and evidence-backed resolution;
record reasons for rejection or deferral. Reviewing and fixing once does not imply
repeated review rounds. Supplied findings use fix mode without a fresh review unless
the user requests one.

## Review loops

For an explicitly requested loop, follow the user's models, reviewer/fixer
counts, lenses, maximum rounds `X`, and exit condition. Apply the defaults and
suggestions in [workflow setup](../references/workflow.md#defaults-and-suggestions)
without duplicating that policy here. Stop early only when no valid actionable
feedback remains and every assigned reviewer completed. User instructions override
those defaults.

Before dispatch, record a compact loop contract in the ledger/handoff: scope and
baseline, reviewer slots with each model/effort/lens, requested parallelism, fixer
model/effort, round cap, early-stop condition, and any per-round changes. Briefly
state that interpretation; ask only if a material ambiguity remains. For example,
two reviewers per round, A at high effort and B at low effort, for up to four
rounds means up to eight reviewer passes; a final round with C is a separate
explicit override, not a reason to replace earlier reviewers.

Check availability before dispatch. If requested models, reasoning settings, or
concurrency cannot be provided, report the constraint and agree on an adjustment;
do not silently substitute models, reduce reviewer count, or call serial work
parallel. Carry the contract forward between rounds unless the user changes it.

One round is one review pass by the requested reviewer group, followed by adjudication and any authorized fixes and verification. Multiple reviewers in that group count as one round, not multiple rounds.

1. Have all reviewers read the current handoff and inspect the same recorded change state. Run independent reviewers concurrently, with distinct lenses when useful. Keep that scope stable until their reports arrive.
2. Adjudicate and deduplicate their feedback. A round is clean only when every assigned reviewer completed and no valid actionable feedback remains; failed or missing reviews are not clean results. Resolve uncertain findings before declaring the round clean.
3. If clean, write the round's final handoff and stop. Otherwise write a review-to-fix handoff containing accepted findings, exact corrective instructions, and required gates.
4. Send the review-to-fix handoff to [fix mode](fix.md). Fixers apply authorized
   corrections in parallel where ownership and dependencies allow and pass affected
   gates. Write a fix-to-review handoff with dispositions, changed state, evidence,
   and outstanding issues.
5. If another round is allowed, reviewers read the new handoff and review the updated work, including regressions from fixes. Otherwise stop at `X` and report the final state. Final authorized fixes may be verified at the cap, but they are not represented as independently reviewed.

An ordinary request for a review loop includes the review/fix cycle; after its
stopping condition, move to the next selected stage or final verification. An
additional review pass requires remaining round allowance. Honor an explicit
read-only or other user-defined arrangement instead. For a read-only loop, carry
findings forward without edits and keep verification read-only.

Track accepted, rejected, fixed, verified, and deferred findings in the round handoffs. Finish when the requested stopping condition is met and every accepted finding has a disposition. Report rounds run, why the loop stopped, unresolved items, whether final fixes received another review, and the final handoff path; testing alone is not a clean review.
