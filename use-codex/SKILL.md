---
name: use-codex
description: Dispatch workers through Codex CLI when a Codex/OpenAI model is requested without native subagent support, or when Codex is explicitly selected as the CLI backend.
---

# Use Codex

Run one bounded assignment through Codex CLI. The caller owns workflow, model
selection, and acceptance; this skill owns the process and session. A new CLI
session does not inherit the caller's conversation.

## Launch

1. **Preflight.** Check `command -v codex` and `codex exec --help`. Use existing
   authentication. Confirm the selected model/effort is supported; an unavailable
   selection or auth failure is a blocker, not permission to substitute a model.
2. **Brief.** Set absolute `project_path`, `brief_path`, `result_path`, and
   `events_path` values in a task-specific temporary folder (except the project).
   Write the objective, relevant context, write boundaries, Git authorization,
   acceptance criteria, and required report into the brief. Keep model, effort,
   and permissions explicit from the caller; inherit CLI defaults only when the
   caller selected that behavior.
3. **Run.** Launch with the brief on stdin and capture the process handle:

   ```bash
   codex exec -C "$project_path" --dangerously-bypass-approvals-and-sandbox --json \
     --output-last-message "$result_path" - < "$brief_path" > "$events_path"
   ```

   Add `--model "$model_id"` for the selected model and, for example,
   `-c 'model_reasoning_effort="high"'` for selected supported effort, replacing
   `high` with the caller's choice. Full permissions are the default within host
   policy; for restrictions, replace the bypass flag with `--sandbox read-only`
   or `--sandbox workspace-write`. Scope in the brief still binds the worker.
   Outside Git, add `--skip-git-repo-check` when needed; creating a repository
   is unnecessary.
4. **Collect.** Record the thread ID from JSON events alongside the process
   handle. Use runtime process waits/continuations until exit; inspect failures,
   terminal events, and the final message. Return session ID, report/artifact
   paths, check evidence, and unresolved items. A launched process or successful
   exit alone does not establish the assignment's acceptance criteria.

For a related follow-up or interrupted run, read
[session reuse](references/sessions.md) before launching another process.
