# Usage help

Start with the user's goal and context. Propose the smallest suitable branch or
combination, then ask only for missing settings of the selected configured
roles. For a multiphase workflow, resolve the complete ready configuration up
front: stage order and checkpoints, owner, model, reasoning effort, worker
count, review/fix caps, integration owner, and stopping rules where relevant.
An unresolved choice can end the turn with one focused question.
Read [workflow setup](workflow.md) for defaults and verification. Help itself
does not dispatch workers or write artifacts.

When no explicit or inherited planner configuration is available, planning uses
the lead/orchestrator's current model and reasoning effort. Do not ask the user
to configure the default planner. If the user explicitly selects a specific
planning model or planning worker, that planner makes architectural decisions
within the lead's scope; the lead owns scope, acceptance, and synthesis.

Plans can be lite or detailed. Honor the user's requested depth; when they leave
it open, choose based on complexity and risk and state that choice before
configured work begins.

Use the intent router in [SKILL.md](../SKILL.md#route-by-intent): an ordinary
issue fix uses execution with built-in checks; supplied review findings use
triage/fix; an explicit plan uses planning; a supplied plan uses execution. A
review may include authorized fixes when requested, while review-only remains
read-only. The longer chain runs only when its stages are selected.

Lightweight examples:

```text
$conductor fix this issue using gpt-5.6-luna at medium
$conductor plan this task, then stop for my approval
$conductor fix these review findings without starting another review

$conductor use a lite plan for this small fix with the current orchestrator
model and reasoning effort; implement with one gpt-5.6-luna worker at medium
reasoning, run built-in checks, and skip review.
```

Multi-stage prompts configure the full selected workflow in one request. Name
each selected stage's owner, model, reasoning effort, worker count, checkpoints,
review/fix caps, integration owner, and stopping rules up front; Conductor may
propose a missing value for acceptance before dispatch. For example:

```text
$conductor plan the fix with one gpt-6-astra planner at high reasoning; after the plan passes its gate, implement it with 3 parallel gpt-5.6-luna subagents at medium reasoning and disjoint ownership; then run up to 3 code-review/fix loops, using 2 parallel gpt-5.6-sol reviewers at high reasoning in each round and up to 3 parallel gpt-5.6-terra review fixers at high reasoning. Stop early when a review round has no actionable findings.

$conductor plan this migration with one gpt-6-astra planner at high reasoning, have 2 parallel gpt-5.6-sol plan reviewers at high reasoning perform up to 2 plan-review/fix loops, and use gpt-5.6-terra plan fixers at high reasoning for accepted findings. Stop after the plan passes review and wait for my approval before implementation.

$conductor execute docs/plan.md with 4 parallel gpt-5.6-luna implementers at medium reasoning and disjoint file ownership; after the implementation gates pass, run one review round with 2 parallel gpt-5.6-sol reviewers at high reasoning, fix accepted findings with gpt-5.6-terra at high reasoning, and have one gpt-6-astra independent verifier at high reasoning check the final acceptance criteria. Do not commit or push.
```

On a later run, reuse the most recent accepted workflow configuration available
in the current conversation or handoff unless the user overrides particular
settings or stages. Do not ask for values already available there, and do not
carry over hidden/global state, the prior task's state, or authorization. This
includes an inherited delegated planner's model, effort, and owner; if no
explicit or inherited planner configuration exists, use the current orchestrator
by default. A one-stage override can be stated concisely:

```text
$conductor reuse the most recent accepted run workflow configuration available
in this conversation or handoff for this related task; override only the
implementation stage with 2 parallel gpt-5.6-luna workers at medium reasoning.
Keep the selected stages, gates, integration owner, and stopping rules.
```

If a run is interrupted, use the latest available handoff or ledger. If those
are missing or stale, reconstruct state from the actual partial work, report
gaps, and avoid inferring authorization for new work.

Explain that Conductor preserves lead context by delegating bounded navigation,
raw reading, implementation, and requested review while the lead scopes,
synthesizes, steers, and accepts evidence. Use native workers when possible;
internal explorers may be selected automatically only for authorized planning or
exploration. User-configured stage settings remain the user's and reviews,
independent verifiers, and later stages remain opt-in.
