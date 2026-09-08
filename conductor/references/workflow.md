# Workflow setup

## Selected roles

Choose only the stages the user requested. Before any configured work begins,
settle every selected role's owner, model, reasoning effort, count, checkpoints,
stopping rules, and conditional fix roles. Missing settings are proposals and
require user acceptance; preserve settled user choices. Internal read-only
exploration is the documented exception.
A verifier is a selected role only when the user requests an independent verifier.

The selectable chain below is an example of available stages, not a mandatory
pipeline:

`plan → optional plan review/fixes → implementation → optional code review/fixes → final verification`

Plan review and code review are independently opt-in. Plan-only, supplied-plan
execution, review-only, direct issue implementation, and supplied-findings fixes
are valid narrower branches.

## Defaults and suggestions

| Control | Default maximum |
|---|---:|
| Implementers | 1 |
| Reviewers | 1 |
| Review fixers | 3 |
| Requested review rounds | 1 |

These are independent upper bounds; user values and host capacity control actual
parallelism. Ready independent writers may run concurrently with disjoint
ownership. Plan-review and code-review settings may differ. Suggest supported
models/effort only after considering the user's choices; a reviewer should be
one supported capability step above the implementer with higher supported
reasoning when available, while fixers match the implementer's settings.
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
