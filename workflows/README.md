# Workflows

Describe the workflow you want; the main agent orchestrates and supervises it
and owns scope, steering, integration, and acceptance. Planning stays with the
main agent unless you select a planner, who owns architecture and plan synthesis.

## Use

Invoke workflows explicitly by name, or through your host's skill-mention syntax.
A bare invocation or `workflows help` explains options without starting work.

```text
Use workflows with one Fable worker at high reasoning to fix this bug.
Use workflows with one Astra planner at high reasoning to plan this migration, then stop.
Use workflows to review these changes, read-only.
```

Choose a whole workflow in one request:

```text
Use workflows to plan [task] with one Astra worker at high reasoning, implement
with two Luna workers at medium in independent tracer-bullet slices, then review
once with one Fable worker at high. You own integration; stop with findings.
```

Models must be available through a compatible backend. The main agent settles
selected stages, role settings, ownership, gates, and stopping rules before work.
Only requested stages run; built-in verification needs no independent reviewer.
Review/fix loops require a round cap and stopping condition.

## Dispatch

Native subagents are preferred. For CLI dispatch, install the matching companion
skill: [use-codex](../use-codex/SKILL.md), [use-claude](../use-claude/SKILL.md), or
[use-glm](../use-glm/SKILL.md). These model-invoked skills own CLI
commands and session handling; the main agent owns assignments and acceptance.
The selected CLI must already be installed and authenticated.

## Continue a run

Reuse accepted workflow settings from the conversation or a supplied handoff,
with explicit overrides. For interrupted work, the main agent reconciles the ledger
and handoffs with actual partial changes before continuing. Settings reuse grants
no new scope or Git authorization. Git writes require an explicit request.

See [usage help](references/help.md) for configuration examples and
[workflow setup](references/workflow.md) for role defaults. The
[skill entrypoint](SKILL.md) routes each selected stage to its instructions.
