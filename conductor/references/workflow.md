# Workflow setup

## Selected roles

Before configured work or internal exploration, settle the entire selected
workflow: stage order; each role's owner, model, effort, count, checkpoints and
stopping rules; conditional fix roles; shared-contract and integration owners.
Reuse the last accepted configuration available in the conversation or supplied
handoff, then merge explicit overrides. Propose genuinely missing role settings
for acceptance; already settled values need no approval again.

Planning uses the current lead and effort unless an explicit or inherited
configuration selects a planning worker/model. An explicitly named planning model
requires a worker even when it matches the lead. That planner owns architecture
and plan synthesis; the lead steers scope and accepts the result. Record runtime
model/effort values only when exposed; otherwise label them current or inherited.

Select only requested stages, for example:

`plan → plan review/fixes → implementation → code review/fixes → verification`

Plan review and code review are independently opt-in. A direct task, plan-only
run, supplied-plan execution, review-only run, or supplied-findings fix can stand
alone. Configure an independent verifier only when explicitly requested.

## Defaults and suggestions

Explicit and inherited settings take precedence. For newly selected worker roles:

| Control | Default maximum |
| --- | ---: |
| Implementers | 1 |
| Reviewers | 1 |
| Review fixers | 3 |
| Requested review rounds | 1 |

These are independent caps, bounded by host capacity. Plan-review and code-review
settings may differ. Suggest a supported reviewer one capability step above the
implementer, with higher supported effort when available; suggest fixers matching
the implementer. Keep these proposals within the user's model constraints.

If effort is not configurable, disclose that. If an explicit model, effort, or
parallel count is unavailable, report the constraint and settle an adjustment
before dispatch; serial work does not satisfy a request for parallel workers.

For the separate internal context-gathering branch, read
[exploration](exploration.md) when planning or exploration needs substantial
source navigation. It does not defer downstream workflow settings.

## Verification

The implementer and lead assess evidence against the selected branch's gates.
This built-in verification adds neither a reviewer nor an independent verifier.
Keep read-only branches' checks read-only. The integration owner verifies the
combined state; individual worker passes cannot establish that result.

Persist the accepted configuration in the run ledger and stage handoffs. Reuse
settings only: a new task supplies its own scope, findings, plan state, round
counters, and Git authorization. Available conversation or handoffs are the
source; do not invent persistent/global settings.
