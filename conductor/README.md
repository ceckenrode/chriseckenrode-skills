# Conductor

Conductor is a user-invoked orchestration skill. It keeps scope, synthesis, and
acceptance with the lead agent while delegating bounded work to native subagents
or compatible CLI workers. Planning stays with the current orchestrator by
default; when the user explicitly requests a specific planning model or a
planning subagent, that planner makes architectural decisions within the lead's
scope and the lead retains scope and acceptance.

## Use

Invoke Conductor explicitly with `$conductor` in Codex, `/conductor` in Claude
Code, or a direct request to use Conductor. A bare invocation or help request
explains and configures a workflow without starting workers or writing files.

```text
$conductor fix this issue using gpt-5.6-luna at medium
$conductor plan this task, then stop for my approval
$conductor review these changes, read-only
```

Selected stages can be configured together in plain language. For a multiphase
workflow, settle the complete configuration up front before dispatch: each
stage's owner, model, reasoning effort, worker count, checkpoints, review/fix
caps, integration owner, and stopping rules as applicable. Parallel writers must
have disjoint ownership.

```text
$conductor plan the fix with one gpt-6-astra planner at high reasoning;
after the plan passes its gate, implement it with 3 parallel gpt-5.6-luna
subagents at medium reasoning and disjoint ownership; then run up to 3
code-review/fix loops, using 2 parallel gpt-5.6-sol reviewers at high reasoning
in each round and up to 3 parallel gpt-5.6-terra review fixers at high reasoning.
Stop early when a review round has no actionable findings.
```

The explicitly selected Astra planner makes architectural decisions for the
accepted scope; the lead integrates the Luna work, owns acceptance, and steers
the Sol/Terra loop.

Conductor supports planning, direct implementation, supplied-plan execution,
review, review/fix loops, and fixes for supplied findings. Only requested stages
run. Reviews and independent verifiers are opt-in; ordinary execution includes
built-in verification without adding either role.

When no explicit or inherited planner configuration is available, planning
defaults to the lead/orchestrator's current model and reasoning effort. Specify
a specific planning model only when you want to override that default and use a
separate planning worker. The multi-stage example above explicitly makes that
override by selecting `gpt-6-astra`.

Planning may be lite or detailed: request the depth you want, or let Conductor
choose based on complexity and risk. A lightweight default-planner run can be
configured as:

```text
$conductor use a lite plan for this small fix with the current orchestrator
model and reasoning effort; implement it with one gpt-5.6-luna worker at medium
reasoning, run built-in checks, and skip review.
```

## Workflow controls

For each separately configured role, specify any choices that matter: owner,
model, reasoning effort, worker count, checkpoints, loop cap, and stopping rule.
Conductor proposes missing settings for acceptance before configured work
begins. Parallel writers must have disjoint ownership.

On a subsequent run, reuse only the most recent accepted workflow configuration
that is available in the current conversation or a supplied handoff unless the
user overrides particular settings or stages. Do not ask for values already
available there, and do not imply hidden or global persistence: prior task state
and authorization do not carry over. This includes an inherited delegated
planner's model, effort, and owner; absent explicit or inherited planner
settings, use the current orchestrator by default. For example:

```text
$conductor reuse the most recent accepted run configuration available in this
conversation or handoff for this related task; override only implementation to
2 parallel gpt-5.6-luna workers at medium reasoning, keeping the other selected
stages, gates, integration owner, and stopping rules.
```

If a run is interrupted, recover from the latest available handoff or ledger. If
those are missing or stale, reconstruct state from the actual partial work,
report gaps, and avoid inferring authorization for new work.

Conductor does not commit, stage, amend, tag, or push unless explicitly asked.
Before repository edits it records pre-existing dirty paths and preserves
unrelated work.

See [SKILL.md](SKILL.md) for the intent router,
[usage help](references/help.md) for more examples, and
[workflow setup](references/workflow.md) for role defaults and verification.
