# GLM session reuse through OpenCode

Wait for the prior process to exit. After an interruption, capture partial work
and output before resuming. Set absolute `project_path`, `followup_path`, and a
fresh `events_path`, plus the recorded `session_id`. Set `model_id` to the GLM
model from the launch contract, defaulting to `zai-coding-plan/glm-5.3` only when
the caller did not select another GLM model.

```bash
model_id="zai-coding-plan/glm-5.3"
opencode run "Follow the attached follow-up brief." --dir "$project_path" \
  --session "$session_id" --model "$model_id" --format json --auto \
  --file "$followup_path" > "$events_path"
```

Preserve the launch contract's GLM model, reasoning variant, and permission
controls. Omit `--auto` for restricted runs; do not loosen configured denials on
resume. Supply the delta, current scope, and relevant failure evidence, letting
the recorded session provide earlier turns. Use the exact ID rather than the
last-session shortcut, and keep each turn's output separate. Collect terminal
evidence using the entrypoint's completion gate.

If the session is missing, report the loss and reconstruct a fresh brief from
saved artifacts before starting a replacement GLM session.
