# Usage help

Identify the goal and smallest matching branch using the
[intent router](../SKILL.md#route-by-intent). Read [workflow setup](workflow.md)
for configuration, planning ownership, role defaults, and verification. Propose
only genuinely missing settings; help itself dispatches nothing and writes no
artifacts.

## One stage

```text
Use workflows with one Fable worker at high reasoning to fix this bug.
Use workflows to write a lite plan for this task, then stop for my approval.
Use workflows with one Astra planner at high reasoning to design this migration.
Use workflows to fix these supplied review findings without another review.
```

`Lite` and `detailed` select plan depth; otherwise choose from complexity and risk.
Model names are examples, subject to backend availability.

## Multiple stages

```text
Use workflows to plan [task] with one Astra worker at high reasoning, implement
with two Luna workers at medium in independent tracer-bullet slices, then review
once with one Fable worker at high. You own integration; stop with findings.

Use workflows to execute [plan] with two Luna workers at medium reasoning.
Then run up to three review/fix rounds with one Fable reviewer at high and one
Luna fixer at medium. You own integration; stop early when a round is clean.
```

For remaining controls, settle checkpoints, shared-contract ownership, and gates
before dispatch. Parallel work requires independent ownership and resources.
CLI dispatch requires the selected companion skill from
[agent dispatch](agent-dispatch.md#backend).

## Reuse and recovery

```text
Use workflows with the last accepted workflow settings from this conversation.
For [new task], change only implementation to two Luna workers at medium reasoning.
```

Reuse available settings under [workflow setup](workflow.md). For an interrupted
run, follow [recovery](context-handoffs.md#recovery); report missing state rather
than inferring new authorization.
