# chriseckenrode-skills

Portable agent skills for orchestrating models, spawning GLM workers, and setting
up Hermes or OpenClaw on Hetzner. Each skill is a self-contained folder with a
`SKILL.md` entrypoint and any supporting scripts or references.

Repository: [ceckenrode/chriseckenrode-skills](https://github.com/ceckenrode/chriseckenrode-skills).

## Skills

| Skill | What it does |
| --- | --- |
| [conductor](conductor/README.md) | User-invoked orchestration aiming to save the lead model's tokens by delegating work to smaller models. The lead owns direction, scope, synthesis, supervision, and verification; planning stays with the lead by default, while an explicitly requested planning worker can make architectural decisions within that scope. Supports parallel work, configurable review loops, and built-in usage help. |
| [spawn-glm](spawn-glm/README.md) | Runs a GLM worker through OpenCode and the Z.AI coding plan. Defaults to `zai-coding-plan/glm-5.3`; respects explicit model choices. Adds no orchestration or review workflow of its own. |
| [hetzner-hermes-claw-box](hetzner-hermes-claw-box/README.md) | User-invoked setup and management for Tailscale-only Hetzner boxes running Hermes or OpenClaw. OpenClaw setup includes a dashboard URL handoff and PWA installation guidance. Credentials and box state stay in a separate working directory, outside the skill. |

Conductor uses the current host's native subagents when available—including
Claude-native subagents in Claude Code—and selects a compatible CLI only when
needed or requested. An explicitly requested `spawn-glm` adapter is optional;
native or compatible CLI dispatch requires no companion skill.

## Install through your agent

Open an agent chat **in the project where you want to use the skill**, then paste
one of these prompts. Installation copies the complete skill folder into the
current agent's supported skill directory; it does not run the skill.

### Install one skill locally

**Conductor**

```text
Install conductor from https://github.com/ceckenrode/chriseckenrode-skills locally into this project.
```

**GLM workers**

```text
Install spawn-glm from https://github.com/ceckenrode/chriseckenrode-skills locally into this project.
```

**Hetzner boxes**

```text
Install hetzner-hermes-claw-box from https://github.com/ceckenrode/chriseckenrode-skills locally into this project.
```

### Install all three locally

```text
Install all three skills from https://github.com/ceckenrode/chriseckenrode-skills locally into this project.
```

### Install globally instead

Use global installation when you want a skill available across projects for the
current agent. Replace the skill name below to install another one.

```text
Install conductor from https://github.com/ceckenrode/chriseckenrode-skills globally for this agent.
```

The installer should follow the current agent's supported skill-discovery layout,
not assume every host uses the same directory. If the agent cannot determine that
layout, it should ask. If a newly installed skill is not visible in the current
chat, start a new chat or reload skills as supported by the host.

### Install from a local clone

When developing the skills, this repository is the source of truth. Symlink each
skill into the host's skills directory so edits here are live without re-copying:

```bash
cd /path/to/chriseckenrode-skills
for s in conductor spawn-glm hetzner-hermes-claw-box; do
  rm -rf ~/.claude/skills/"$s"   # remove a stale copy first; ln would otherwise link inside it
  ln -s "$PWD/$s" ~/.claude/skills/"$s"
done
```

For Codex use `~/.codex/skills` instead.

## Use the skills

Conductor and hetzner-hermes-claw-box are user-invoked only; the agent must not
activate either on its own. Start
with `$conductor help` in Codex or `/conductor help` in Claude Code for examples
and guidance. Start with the goal, then settle the complete configuration for
every selected stage up front: owner, model, reasoning effort, worker count,
checkpoints, review/fix caps, integration owner, and stopping rules where
relevant. Reviews remain opt-in. Describe the arrangement you want in plain
language.

After an authorized planning or exploration request starts, Conductor may
automatically delegate bounded, read-only navigation and raw-context gathering to
suitable small native models, which return distilled, anchored evidence while the
lead retains scope and acceptance. An explicitly selected planning worker owns
the architectural and planning decisions within that scope. This does not run
from help or a bare invocation, and it does not replace settings for
implementation, review, fixes, or final verification.

When no explicit or inherited planner configuration is available, planning uses
the current orchestrator model and reasoning effort by default; no
planner configuration is required. If you explicitly request a specific
planning model or a planning subagent, Conductor delegates planning to that
worker: it makes the architectural decisions within the lead's scope, while the
lead retains scope, acceptance, and synthesis. Ask for a lite
or detailed plan, or let Conductor choose the depth from complexity and risk;
settle any resulting stage settings before work starts. The multi-stage example
below explicitly selects `gpt-6-astra` as its planner.

After installation, refer to the skill by name in ordinary chat. Replace the
bracketed task or path with your own. Hosts that support skill mentions can also
use `$conductor`, `$spawn-glm`, or `$hetzner-hermes-claw-box`.

**Plan and implement with delegated workers:**

```text
Use conductor to plan and implement [task] as tracer-bullet slices. Make the
first slice prove the minimal real path end to end, expand it in later slices,
parallelize only independent slices, and verify each working increment. No review
loop.
```

**Configure a multi-stage workflow:**

```text
$conductor plan the fix with one gpt-6-astra planner at high reasoning;
after the plan passes its gate, implement it with 3 parallel gpt-5.6-luna
subagents at medium reasoning and disjoint ownership; then run up to 3
code-review/fix loops, using 2 parallel gpt-5.6-sol reviewers at high reasoning
in each round and up to 3 parallel gpt-5.6-terra review fixers at high reasoning.
Stop early when a review round has no actionable findings.
```

**Use the default planner for a lightweight workflow:**

```text
$conductor use a lite plan for this small fix with the current orchestrator
model and reasoning effort; then implement it with one gpt-5.6-luna worker at
medium reasoning, run the built-in checks, and do not start a review loop.
```

**Reuse accepted settings on the next run, with one override:**

```text
$conductor use the most recent accepted run workflow configuration available in
this conversation or handoff for this related task; override only the
implementation stage with 2 parallel gpt-5.6-luna workers at medium reasoning.
Keep its selected stages, gates, integration owner, stopping rules, and any
delegated planner model, effort, and owner. If no explicit or inherited planner
configuration exists, use the current orchestrator by default. Do not reuse the
prior task's state or authorization.
```

Conductor can recover an interrupted run from the latest available handoff or
ledger. If those are missing or stale, it reconstructs state from the actual
partial work, reports gaps, and does not infer authorization for new work.

**Direct issue fix:**

```text
Use conductor with gpt-5.6-luna at medium to fix this issue. Run built-in checks and report; no review loop.
```

**Plan without implementing:**

```text
Use conductor to plan [task]. Write the plan to [path]. Include task dependencies, detailed implementation guidance, and verification gates. Stop after planning.
```

**Request a review loop:**

```text
Use conductor to review and fix [scope]. Explicitly use two reviewers per round,
for up to three rounds or until there is no valid actionable feedback. Verify
fixes and report anything unresolved.
```

**Delegate to GLM:**

```text
Use spawn-glm to investigate [question] in this project. Keep the assignment read-only and return concise findings with file references.
```

**Set up an OpenClaw box:**

```text
Use hetzner-hermes-claw-box to help me set up OpenClaw on Hetzner. Store configuration and box state in [separate working directory], outside the skill folder. Let me enter secrets and confirm paid provisioning myself. When ready, give me the verified Tailscale dashboard URL and instructions to install its PWA.
```

## Before running

- **Permissions:** Conductor and spawn-glm default to full-permission worker execution, subject to host restrictions. Request restricted execution explicitly when needed; assignment scope still applies.
- **GLM:** Requires OpenCode installed and authenticated for the Z.AI coding plan, with the requested model available. Installing the skill does not install or authenticate OpenCode.
- **Hetzner:** Requires provider access, local command-line dependencies, and Tailscale setup. Provisioning incurs cloud charges and requires confirmation. See the [Hetzner guide](hetzner-hermes-claw-box/README.md) for prerequisites and commands.
- **Secrets:** Never put live credentials or box inventory in this repository. Static templates are not live state.
