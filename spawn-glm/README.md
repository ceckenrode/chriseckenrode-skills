# Spawn GLM

Spawn GLM runs one bounded worker assignment through the OpenCode CLI and the
Z.AI coding plan. It is a backend adapter, not an orchestration or review
workflow. The default model is `zai-coding-plan/glm-5.3`; explicit model and
reasoning-variant choices are preserved.

## Prerequisites

- OpenCode installed and available as `opencode`.
- Authentication for the Z.AI coding plan.
- The requested model and reasoning variant available in the installed CLI.

## Use through an agent

Ask the agent to use `spawn-glm` and give it a bounded objective, project, scope,
acceptance criteria, and expected evidence:

```text
Use spawn-glm to investigate why the API integration tests are flaky in this
project. Keep the assignment read-only and return concise findings with file and
line references.
```

The skill writes a self-contained brief to a task-specific temporary directory,
runs the worker in the background, extracts only the session ID, errors, and
final response from the JSON event log, and verifies the reported result.

## Run the adapter directly

```bash
bash /path/to/spawn-glm/scripts/glm.sh \
  --project /absolute/project/path \
  --prompt-file /absolute/path/to/brief.md \
  > /absolute/path/to/tmp/glm-task.jsonl 2>&1
```

Optional flags are `--model`, `--variant`, `--session`, `--agent`, `--title`, and
`--permissions full|configured`. Full permissions are the default. Use
`--permissions configured` to preserve the current OpenCode permission settings.
A read-only brief remains an assignment constraint and does not itself create a
host-enforced sandbox.

For follow-up work, create a new brief and reuse the returned session ID with
`--session`. See [SKILL.md](SKILL.md) for the full dispatch and result-extraction
procedure.
