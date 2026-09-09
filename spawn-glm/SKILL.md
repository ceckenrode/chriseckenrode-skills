---
name: spawn-glm
description: Spawn a GLM worker when the user requests a GLM model or GLM subagent, using OpenCode with the Z.AI coding plan.
---

# Spawn GLM

Run the user's assignment as an OpenCode CLI worker. This is a backend adapter; it adds no planning stages or review loops.

1. Confirm the project and a bounded assignment. Write a brief containing the objective, context/paths, read or write scope, acceptance criteria, and expected result to a task-specific temporary file. The brief must be self-contained: the OpenCode session cannot see this conversation. When the `workflows` skill is installed, use the brief structure in its `references/agent-dispatch.md`.
2. Check `command -v opencode`, `opencode run --help`, and `opencode models zai-coding-plan`. The wrapper defaults to `zai-coding-plan/glm-5.3`; preserve any explicit model/provider. If unavailable, report the mismatch rather than substituting a model.
3. The wrapper is `scripts/glm.sh` under this skill's base directory (reported when the skill loads). Launch it with all output redirected into the task's temporary folder so the JSON event stream never enters your context:

   ```bash
   bash "<skill base directory>/scripts/glm.sh" \
     --project /absolute/project/path \
     --prompt-file /absolute/path/to/brief.md \
     > /absolute/path/to/tmp/glm-<task>.jsonl 2>&1
   ```

   Optional flags: `--model <model-or-provider/model>`, `--variant <effort>`, `--session <id>`, `--agent <configured-role>`, `--title <title>`, `--permissions full|configured`. Omit variant for provider-default effort. Verify explicitly requested variants with the installed CLI; preserve the user's choice or report incompatibility.
4. Run it in the background with the host's process tools (in Claude Code: Bash with `run_in_background`, then read the result when the process exits). Do not read the log whole; extract the session ID, error events, and the final response with `jq`:

   ```bash
   jq -r '.sessionID' /absolute/path/to/tmp/glm-<task>.jsonl | head -1
   jq -c 'select(.type | test("error"))' /absolute/path/to/tmp/glm-<task>.jsonl
   jq -r 'select(.type == "text") | .part.text' /absolute/path/to/tmp/glm-<task>.jsonl | tail -1
   ```

   Inspect error events and the final response; verify requested files or results before reporting completion. For related follow-ups, use `--session` with a new brief file and the same model/variant selections.

The wrapper passes prompt text as one argument and streams OpenCode's JSON events. Full permissions are the default: `OPENCODE_PERMISSION='{"*":"allow"}'` plus `--auto`. If the user requests existing configured restrictions, use `--permissions configured`, which preserves the permission environment and omits `--auto`. Read-only investigation remains an assignment constraint; agent-specific or host-enforced denials may still apply. Report auth or permission failures with their cause.

Permission mechanics: [OpenCode permissions](https://opencode.ai/docs/permissions/) and [CLI environment variables](https://opencode.ai/docs/cli/#environment-variables).
