# chriseckenrode-skills

Portable agent skills for orchestrating models, spawning GLM workers, and setting
up Hermes or OpenClaw on Hetzner. Each skill is a self-contained folder with a
`SKILL.md` entrypoint and any supporting scripts or references.

Repository: [ceckenrode/chriseckenrode-skills](https://github.com/ceckenrode/chriseckenrode-skills).

## Skills

| Skill | What it does |
| --- | --- |
| [conductor](conductor/SKILL.md) | User-invoked orchestration aiming to save the lead model's tokens by delegating work to smaller models. The lead owns direction, planning, supervision, and verification. Supports parallel work, configurable review loops, and built-in usage help. |
| [spawn-glm](spawn-glm/SKILL.md) | Runs a GLM worker through OpenCode and the Z.AI coding plan. Defaults to `zai-coding-plan/glm-5.3`; respects explicit model choices. Adds no orchestration or review workflow of its own. |
| [hetzner-hermes-claw-box](hetzner-hermes-claw-box/SKILL.md) | User-invoked setup and management for Tailscale-only Hetzner boxes running Hermes or OpenClaw. OpenClaw setup includes a dashboard URL handoff and PWA installation guidance. Credentials and box state stay in a separate working directory, outside the skill. |

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
and guidance. Start with the goal, then settle the user-configured stages' models and
reasoning effort up front; reviews remain opt-in. Describe the arrangement you
want in plain language.

After an authorized planning or exploration request starts, Conductor may
automatically delegate bounded, read-only navigation and raw-context gathering to
suitable small native models, which return distilled, anchored evidence while the
orchestrator retains architecture, planning, and decisions. This does not run
from help or a bare invocation, and it does not replace settings for
implementation, review, fixes, or final verification.

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
