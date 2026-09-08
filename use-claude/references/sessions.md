# Claude session reuse

Wait for the prior process to exit before sending a follow-up to its session.
If interrupted, collect partial output and changed artifacts first. Set absolute
`project_path`, `followup_path`, and a fresh `result_path`; use the recorded
`session_id` rather than the most-recent-conversation shortcut.

```bash
(cd "$project_path" && claude -p --resume "$session_id" \
  --dangerously-skip-permissions --output-format json \
  < "$followup_path" > "$result_path")
```

The follow-up supplies the delta, current scope, and failure evidence. Reapply
selected model, effort, and output options from the launch contract. For a
restricted run, replace the bypass flag with the same permission/tool controls
used initially; a resume must not broaden access.

Keep session persistence enabled when follow-ups are needed. If a session cannot
be resumed, report that loss and build a fresh brief from saved artifacts. Collect
the result using the entrypoint's completion gate; a resumed ID is not completion.
