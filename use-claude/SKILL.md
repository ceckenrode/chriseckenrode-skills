---
name: use-claude
description: Dispatch via Claude Code CLI when the host's native subagent tool cannot provide a user-requested model, or the user explicitly selects Claude Code.
---

# Use Claude

Run one bounded assignment through Claude Code CLI. The caller owns workflow,
model selection, and acceptance; this skill owns the process and session.
Ordinary native Claude subagents remain with the host's native dispatcher.

## Launch

1. **Preflight.** Check `command -v claude` and `claude --help`. Use existing
   authentication and validate the selected model/effort. Missing authentication
   or an unavailable selection is a blocker; retain the caller's model choice.
2. **Brief.** Set absolute `project_path`, `brief_path`, and `result_path` values;
   keep the brief and output in a task-specific temporary folder. A new session
   needs the objective, relevant context, write boundaries, Git authorization,
   acceptance criteria, and required report. It has no parent conversation.
3. **Run.** Start in the project with stdin containing the brief:

   ```bash
   (cd "$project_path" && claude -p --dangerously-skip-permissions \
     --output-format json < "$brief_path" > "$result_path")
   ```

   Add `--model "$model_id"` and `--effort "$effort"` for the caller's supported
   selections. Inherit CLI defaults only when the caller selected that behavior.
   Full permissions are the default within host policy; for restrictions, omit
   the bypass flag and use the requested `--permission-mode` and tool controls
   supported by the installed CLI. Read-only scope still binds the worker.
   For live progress, replace the output format with `stream-json` and add
   `--verbose`; save the event stream instead of expecting one JSON object.
4. **Collect.** Capture the process handle and `session_id` from JSON. Wait for
   process exit using runtime continuation tools. Inspect the terminal result,
   error status, and report; return the session ID, artifact paths, evidence,
   and unresolved items. Process success alone does not prove task acceptance.

For related follow-ups or recovery, read [session reuse](references/sessions.md).
For version-specific behavior, consult the installed help and
[programmatic usage documentation](https://code.claude.com/docs/en/headless).
