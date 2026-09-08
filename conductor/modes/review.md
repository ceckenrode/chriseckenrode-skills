# Requested review

## Scope and dispatch

Read the incoming stage or previous-round handoff. Use the user's files, diff, baseline, or plan. After execution, default to task-owned changes; for standalone review, identify scope from context and clarify material ambiguity. If no handoff exists, establish a compact starting-state handoff from the plan and a delegated diff summary.

Honor specified models, effort, reviewer counts, lenses, and format. Otherwise use one reviewer with runtime defaults. Supply the relevant plan contract, design rationale, binding examples/interfaces, review scope, and gate evidence.

Reviewers are read-only. Request concrete defects introduced by the change, supported by location, impact/trigger, severity, and evidence. Check plan conformance, correctness, regressions, specified edge cases, and whether verification demonstrates the claimed behavior. Code that matches a flawed plan can still be defective; report the flaw and its impact so the orchestrator can revise the decision. A no-findings report must still state verification limits.

## Findings and fixes

Deduplicate reports and adjudicate findings using the intended behavior and supporting evidence. Ask workers for targeted evidence when a claim needs clarification. Separate actionable defects from unsupported findings and optional preferences. A review-only request ends with the findings report.

If fixes are requested, assign accepted findings with write ownership, explicit corrective instructions, expected behavior, and affected verification gates. Require gate evidence after fixes, including integration checks when shared behavior changed. Reviewing and fixing once does not imply repeated review rounds.

## Review loops

For an explicitly requested loop, follow the user's models, reviewer/fixer counts, lenses, maximum rounds `X`, and exit condition. If unspecified, state a fallback of one reviewer, a fixer as needed, and at most three rounds, stopping early when no valid actionable feedback remains. User instructions override these defaults.

One round is one review pass by the requested reviewer group, followed by adjudication and any authorized fixes and verification. Multiple reviewers in that group count as one round, not multiple rounds.

1. Have all reviewers read the current handoff and inspect the same recorded change state. Run independent reviewers concurrently, with distinct lenses when useful. Keep that scope stable until their reports arrive.
2. Adjudicate and deduplicate their feedback. A round is clean only when every assigned reviewer completed and no valid actionable feedback remains; failed or missing reviews are not clean results. Resolve uncertain findings before declaring the round clean.
3. If clean, write the round's final handoff and stop. Otherwise write a review-to-fix handoff containing accepted findings, exact corrective instructions, and required gates.
4. Have fixers read that handoff, apply authorized corrections in parallel where ownership and dependencies allow, and pass affected gates. Write a fix-to-review handoff with dispositions, changed state, evidence, and outstanding issues.
5. If another round is allowed, reviewers read the new handoff and review the updated work, including regressions from fixes. Otherwise stop at `X` and report the final state. Final authorized fixes may be verified at the cap, but they are not represented as independently reviewed.

An ordinary request for a review loop includes the review/fix/review cycle; honor an explicit read-only or other user-defined arrangement instead. For a read-only loop, carry findings forward without edits and avoid re-reviewing unchanged work unless the requested lenses or instructions make another pass useful.

Track accepted, rejected, fixed, verified, and deferred findings in the round handoffs. Finish when the requested stopping condition is met and every accepted finding has a disposition. Report rounds run, why the loop stopped, unresolved items, whether final fixes received another review, and the final handoff path; testing alone is not a clean review.
