# CLI workers

These are optional backend recipes, not assumptions about the orchestrator's host. Use the current host's native subagents first unless the user explicitly requests a CLI. Select a compatible available fallback using [agent dispatch](agent-dispatch.md#backend), then read only its section below. Other hosts and CLIs are allowed; discover their actual invocation, permissions, and session APIs before use.

Use a task-specific temporary directory for briefs and output. Supply a self-contained brief: a new CLI session has no parent conversation unless explicitly resumed. Run in the intended project, use existing authentication, and capture the process handle plus returned session ID.

Check the installed CLI's help before first use; supported flags can change. Preserve requested models and effort; omit overrides when unspecified. The commands below use full permissions by default, as requested. Use restricted modes only when the user requests them or the host requires them; report host-enforced limits.

## Codex

Use when the user explicitly requests Codex CLI, or when it is the selected compatible fallback. It is not the default for every host.

Preflight: `command -v codex` and `codex exec --help`.

Set `project_path`, `brief_path`, and `result_path` to absolute paths. Launch:

```bash
codex exec -C "$project_path" --dangerously-bypass-approvals-and-sandbox --json \
  --output-last-message "$result_path" - < "$brief_path"
```

Add `--model "$model_id"` only for a selected model, and `-c 'model_reasoning_effort="high"'` only for a selected supported effort (replace `high` as requested). If the user requests sandboxing, replace the bypass flag with `--sandbox read-only` or `--sandbox workspace-write`. For a directory outside Git, add `--skip-git-repo-check` when needed; this does not require creating a repository.

Capture the thread/session ID from JSON events. For related follow-ups, inspect `codex exec resume --help` and resume that exact session from the same project:

```bash
cd "$project_path" && codex exec resume "$session_id" \
  --dangerously-bypass-approvals-and-sandbox --json - < "$followup_path"
```

Resume retains session context; supply the delta and preserve model selections. For a user-restricted session, omit the bypass flag and preserve that session's restrictions. An unavailable model or auth failure is a reported blocker, not permission to change providers.

## Claude Code

Use when the user explicitly requests Claude Code CLI, or when it is the selected compatible fallback for a worker unavailable natively. In Claude Code, ordinary Claude worker requests use native Claude subagents, not nested `claude -p` sessions.

Preflight: `command -v claude` and `claude --help`.

Start a non-interactive worker in the intended project, with the brief on stdin:

```bash
cd "$project_path" && claude -p --dangerously-skip-permissions \
  --output-format json < "$brief_path"
```

Add `--model "$model_id"` and `--effort "$effort"` only when selected and supported. For streaming progress use `--output-format stream-json --verbose`. If the user requests restrictions, omit the bypass flag and use the requested permission/tool settings. Read-only investigation remains an assignment constraint even when full permissions are enabled.

Capture `session_id` from JSON. Continue related work using the explicit ID:

```bash
cd "$project_path" && claude -p --resume "$session_id" --dangerously-skip-permissions \
  --output-format json < "$followup_path"
```

## Completion

Use the runtime's process wait/continuation tools for long runs. A launch or session ID is not completion. Wait for exit, inspect terminal error/result events and the final report, then verify the deliverable against acceptance criteria. Return only the relevant result and evidence to the conductor. Resume a known session instead of using an ambiguous "last session" flag.
