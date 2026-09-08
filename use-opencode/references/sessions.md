# OpenCode session reuse

Wait for the prior process to exit; after interruption, capture partial work and
output before resuming. Set absolute `project_path`, `followup_path`, and a fresh
`events_path`, plus the recorded `session_id` and selected `model_id`.

```bash
opencode run "Follow the attached follow-up brief." --dir "$project_path" \
  --session "$session_id" --model "$model_id" --format json --auto \
  --file "$followup_path" > "$events_path"
```

Preserve the launch contract's reasoning variant and permission controls. Omit
`--auto` for restricted runs; do not loosen configured denials on resume. Supply
the delta and current scope, letting the recorded session provide earlier turns.
Use the exact ID rather than the last-session shortcut, and keep each turn's
output separate. Collect terminal evidence using the entrypoint's completion gate.

If the session is missing, report the loss and reconstruct a fresh brief from
saved artifacts before starting a replacement.
