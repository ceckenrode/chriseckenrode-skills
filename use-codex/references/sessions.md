# Codex session reuse

Read `codex exec resume --help`; resume options can differ from initial launch.
Wait for the previous process to exit, or stop it through the runtime's process
controls and collect partial output before resuming the same session.

Set absolute `project_path`, `followup_path`, `events_path`, and `result_path`,
and use the recorded `session_id`. The follow-up contains the delta, current
scope, and relevant failure evidence; session context supplies earlier turns.

```bash
(cd "$project_path" && codex exec resume "$session_id" \
  --dangerously-bypass-approvals-and-sandbox --json \
  --output-last-message "$result_path" - < "$followup_path" > "$events_path")
```

Reapply the selected model and effort options from the launch contract. For a
restricted run, omit the bypass flag and explicitly preserve its sandbox and
approval settings through the installed version's supported resume/config
options; do not assume session history restores runtime restrictions. Use a fresh
restricted session with a handoff if those settings cannot be preserved.

Use a new output path per turn. Collect completion as in the entrypoint. An exact
session ID prevents attaching to another task; avoid the ambiguous last-session
shortcut. If the session is missing, rebuild context from saved artifacts and
report the loss before starting a replacement.
