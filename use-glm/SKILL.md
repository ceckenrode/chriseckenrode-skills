---
name: use-glm
description: Dispatch GLM workers through OpenCode when a GLM model is requested without native subagent support, or when OpenCode is explicitly selected as the CLI backend.
---

# Use GLM

Run one bounded GLM assignment through OpenCode CLI. The caller owns workflow,
model selection, and acceptance; this skill owns the process and session. Default
to `zai-coding-plan/glm-5.3` unless the caller selects another GLM model. This
skill does not dispatch non-GLM models through OpenCode.

When the `spawn-glm` skill is installed and the caller explicitly requests its
low-level wrapper, load it for the wrapper recipe while preserving this skill's
GLM-only routing and the caller's model choice.

## Launch

1. **Preflight.** Check `command -v opencode`, `opencode run --help`, and
   `opencode models zai-coding-plan --verbose`. Inspect configured providers with
   `opencode auth list`. Use existing authentication; a model listing alone does
   not prove authentication works. Confirm the selected GLM provider/model and
   supported reasoning variant. An unavailable selection or authentication
   failure is a blocker, not permission to substitute a provider or non-GLM model.
2. **Brief.** Set absolute `project_path`, `brief_path`, and `events_path` values;
   keep the brief and output in a task-specific temporary folder. Include the
   objective, relevant context, write boundaries, Git authorization, acceptance
   criteria, and required report. A new CLI session has no parent conversation.
3. **Run.** Set `model_id` to the caller's selected GLM model, or to
   `zai-coding-plan/glm-5.3` by default:

   ```bash
   model_id="zai-coding-plan/glm-5.3"
   opencode run "Follow the attached worker brief." --dir "$project_path" \
     --model "$model_id" --format json --auto --file "$brief_path" > "$events_path"
   ```

   Add `--variant "$effort"` only for a selected, supported GLM variant; variants
   are provider-specific. `--auto` approves permissions not explicitly denied and
   retains configured denials. Use it only where supported and allowed by the
   host. For restricted execution, omit it and preserve the caller's permission
   settings. A permission failure is a blocker, not permission to weaken rules.
4. **Collect.** Capture the process handle and returned session ID from JSON
   events. Wait for exit, inspect error events and the completed response, and
   return the session ID, artifact paths, evidence, and unresolved items. A
   successful launch or exit alone does not prove acceptance.

For a related follow-up or interrupted run, read
[session reuse](references/sessions.md) before launching another process. If
installed flags differ, consult [OpenCode CLI documentation](https://opencode.ai/docs/cli/)
and [permission configuration](https://opencode.ai/docs/permissions/) before
adapting them.
