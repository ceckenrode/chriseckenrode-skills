# chriseckenrode-skills

Portable skills for coordinating agents, dispatching CLI workers, and managing
Hermes or OpenClaw on Hetzner.

## Skills

| Skill | Purpose |
| --- | --- |
| [conductor](conductor/README.md) | Coordinate planning, implementation, and optional review across selected models. |
| [use-codex](use-codex/SKILL.md) | Dispatch and resume workers through Codex CLI. |
| [use-claude](use-claude/SKILL.md) | Dispatch and resume workers through Claude Code CLI. |
| [use-glm](use-glm/SKILL.md) | Dispatch GLM workers through OpenCode. Defaults to zai-coding-plan/glm-5.3. |
| [spawn-glm](spawn-glm/README.md) | Run GLM workers through OpenCode and the Z.AI coding plan. |
| [hetzner-hermes-claw-box](hetzner-hermes-claw-box/README.md) | Set up and manage Tailscale-only Hetzner boxes for Hermes or OpenClaw. |

## Install

Paste this into an agent chat in your project:

```text
Install <skill-name> from https://github.com/ceckenrode/chriseckenrode-skills locally into this project.
```

Replace `<skill-name>` with any skill in this project (e.g., `conductor`).
Conductor uses native subagents when available; install the matching CLI skill
when you need a CLI backend. CLI skills require that CLI installed and authenticated.

## Use the skills

Invoke Conductor and the Hetzner skill explicitly. CLI skills and `spawn-glm`
can be selected by the agent. Use skill names in plain language, or your host's
skill-mention syntax. Ask for `conductor help` to explore workflow options.

Conductor settles selected stages and worker settings up front. Planning stays
with the lead unless you name a planner; reviews are opt-in. The lead steers,
integrates, and accepts results. Model names below require a compatible backend.
Workers default to full permissions within host restrictions; request restricted
execution when needed.

**Plan → implement → review:**

```text
Use conductor to plan [task] with one Astra worker at high reasoning, implement
with two Luna workers at medium in independent tracer-bullet slices, then review
once with one Fable worker at high. You own integration; stop with findings.
```

**Delegate one task:**

```text
Use conductor with one Fable worker at high reasoning to fix [bug] and verify it.
```

**Delegate planning:**

```text
Use conductor with one Astra planner at high reasoning to design [feature].
Write the plan to [path] and stop after planning.
```

**GLM:**

```text
Use glm 5.3 with max reasoning to diagnose this bug.
```

**Hetzner:**

```text
Use hetzner-hermes-claw-box to set up OpenClaw on Hetzner. Keep box state in
[separate working directory] and give me the verified dashboard URL.
```

For prerequisites and provisioning guidance, see the
[Hetzner guide](hetzner-hermes-claw-box/README.md).
