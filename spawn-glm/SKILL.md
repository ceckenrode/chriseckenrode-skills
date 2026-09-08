---
name: spawn-glm
description: Spawn a GLM worker when the user requests a GLM model or GLM subagent, using OpenCode with the Z.AI coding plan.
---

# Spawn GLM

Run the user's assignment as an OpenCode CLI worker. This is a backend adapter; it adds no planning stages or review loops.

1. Confirm the project and a bounded assignment. Write a brief containing the objective, context/paths, read or write scope, acceptance criteria, and expected result to a task-specific temporary file.
2. Check `command -v opencode`, `opencode run --help`, and `opencode models zai-coding-plan`. The wrapper defaults to `zai-coding-plan/glm-5.3`; preserve any explicit model/provider. If unavailable, report the mismatch rather than substituting a model.
3. Resolve this skill's folder and launch its wrapper:

   ```bash
   bash /absolute/path/to/spawn-glm/scripts/glm.sh \
     --project /absolute/project/path \
     --prompt-file /absolute/path/to/brief.md
   ```

   Optional flags: `--model <model-or-provider/model>`, `--variant <effort>`, `--session <id>`, `--agent <configured-role>`, `--title <title>`, `--permissions full|configured`. Omit variant for provider-default effort. Verify explicitly requested variants with the installed CLI; preserve the user's choice or report incompatibility.
4. Capture the process handle and session ID from JSON output. Wait for exit with the runtime's process tools. Inspect error events and the final response; verify requested files or results before reporting completion. For related follow-ups, use `--session` with a new brief file and the same model/variant selections.

The wrapper passes prompt text as one argument and streams OpenCode's JSON events. Full permissions are the default: `OPENCODE_PERMISSION='{"*":"allow"}'` plus `--auto`. If the user requests existing configured restrictions, use `--permissions configured`, which preserves the permission environment and omits `--auto`. Read-only investigation remains an assignment constraint; agent-specific or host-enforced denials may still apply. Report auth or permission failures with their cause.

Permission mechanics: [OpenCode permissions](https://opencode.ai/docs/permissions/) and [CLI environment variables](https://opencode.ai/docs/cli/#environment-variables).
