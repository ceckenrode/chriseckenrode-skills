# chriseckenrode-skills

Portable agent skills for orchestrating models, spawning GLM workers, and setting
up Hermes or OpenClaw on Hetzner. Each skill is a self-contained folder with a
`SKILL.md` entrypoint and any supporting scripts or references.

Repository: [ceckenrode/chriseckenrode-skills](https://github.com/ceckenrode/chriseckenrode-skills).

## Skills

| Skill | What it does |
| --- | --- |
| [conductor](conductor/SKILL.md) | Coordinates other models while the orchestrator owns direction, planning, supervision, and verification. Splits work for parallel execution, writes detailed worker briefs, and carries context through handoffs. Review loops are optional. |
| [spawn-glm](spawn-glm/SKILL.md) | Runs a GLM worker through OpenCode and the Z.AI coding plan. Defaults to `zai-coding-plan/glm-5.3`; respects explicit model choices. Adds no orchestration or review workflow of its own. |
| [hetzner-hermes-claw-box](hetzner-hermes-claw-box/SKILL.md) | Sets up and manages Tailscale-only Hetzner boxes running Hermes or OpenClaw. OpenClaw setup includes a dashboard URL handoff and PWA installation guidance. Credentials and box state stay in a separate working directory, outside the skill. |

Conductor uses the current host's native subagents when available—including
Claude-native subagents in Claude Code—and selects a compatible CLI only when
needed or requested. It does not require GLM; install `spawn-glm` as well if you
want GLM workers.

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

## Use the skills

After installation, refer to the skill by name in ordinary chat. Replace the
bracketed task or path with your own. Hosts that support skill mentions can also
use `$conductor`, `$spawn-glm`, or `$hetzner-hermes-claw-box`.

**Plan and implement with delegated workers:**

```text
Use conductor to plan and implement [task]. Parallelize independent work and verify the result. No review loop.
```

**Plan without implementing:**

```text
Use conductor to plan [task]. Write the plan to [path]. Include task dependencies, detailed implementation guidance, and verification gates. Stop after planning.
```

**Request a review loop:**

```text
Use conductor to review and fix [scope]. Use two reviewers per round, for up to three rounds or until there is no valid actionable feedback. Verify fixes and report anything unresolved.
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
