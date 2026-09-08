# Workflow setup

## Selected roles

Choose only the stages the user requested. Before any configured work or
internal exploration begins, resolve the complete selected workflow: stage
sequence, each role's owner, model, reasoning effort, count, checkpoints,
stopping rules, conditional fix roles, integration owner, and shared-contract
owner. Reuse the last accepted configuration from the available conversation or
the supplied ledger/handoff, then merge explicit changes in the new request.
Settled or inherited values do not need approval again; genuinely missing values
are proposals requiring user acceptance. Internal exploration does not defer
downstream configuration.
A verifier is a selected role only when the user requests an independent verifier.
Planning defaults to the lead/orchestrator using its current model and reasoning
effort only when neither the new request nor the inherited configuration selects
a planning worker/model, so it is not a separately configured role and needs no
planner-model question. Configure and dispatch a planning role when the user
explicitly names a planning model or asks another agent/subagent to plan, even
when the named model matches the current model. Preserve any explicit planning
effort. A
planning worker owns architectural decisions and synthesis within the accepted
scope; the lead steers scope and accepts the result. Record the active planner's
model/effort only when exposed by the runtime; otherwise label it current or
inherited rather than fabricating a value or asking the user to identify it.

The selectable chain below is an example of available stages, not a mandatory
pipeline:

`plan → optional plan review/fixes → implementation → optional code review/fixes → final verification`

Plan review and code review are independently opt-in. Plan-only, supplied-plan
execution, review-only, direct issue implementation, and supplied-findings fixes
are valid narrower branches.

## Defaults and suggestions

When no planning worker or planning model is explicitly requested and no
inherited planning configuration exists, the lead/orchestrator plans with its
current model and reasoning effort. Do not turn that default into an unresolved
setting or silently delegate planning to a worker. Explicit or inherited
settings take precedence over the suggestions below; defaults apply only to
genuinely new roles.

| Control | Default maximum |
|---|---:|
| Implementers | 1 |
| Reviewers | 1 |
| Review fixers | 3 |
| Requested review rounds | 1 |

These are independent upper bounds; user values and host capacity control actual
parallelism. Ready independent writers may run concurrently with disjoint
ownership. Plan-review and code-review settings may differ. Suggest supported
models/effort only after considering explicit and inherited settings; a reviewer
should be one supported capability step above the implementer with higher
supported reasoning when available, while fixers match the implementer's
settings.
If the host cannot configure effort, disclose `not configurable`; if an explicitly
requested model/effort is unsupported, disclose it and agree on an adjustment.

## Verification

Verification is required evidence that the selected branch's final state meets
its gates, assessed by the implementer and lead/orchestrator using checks and
acceptance evidence. It is not an extra role or review round. An independent
verifier runs only when the user requests one; then its owner, model, and effort
are configured with the other selected roles. Ordinary direct fixes do not ask
for verifier settings. Read-only branches keep verification read-only.

Persist the accepted selected configuration in the ledger and carry it through
handoffs. Create a plan artifact only when plan production is selected; a
supplied chat plan remains usable without creating a replacement file.

Configuration reuse applies only to workflow settings. Do not inherit the old
task's scope, findings, plan state, round counters, or Git authorization; those
come from the new request and its supplied artifacts. Do not invent persistent
memory or global settings when no conversation or handoff provides a settled
value.
