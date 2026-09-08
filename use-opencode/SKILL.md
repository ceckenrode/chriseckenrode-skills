---
name: use-opencode
description: Dispatch workers through OpenCode CLI when explicitly requested or when another skill selects OpenCode as its CLI backend.
---

# Use OpenCode

Run one bounded assignment through OpenCode CLI. The caller owns workflow, model
selection, and acceptance. For an explicitly requested `spawn-glm` adapter, load
that skill instead; its provider defaults and wrapper recipes belong there.

## Launch

1. **Preflight.** Check `command -v opencode`, `opencode run --help`, and
   `opencode models --help`. Inspect available providers with `opencode auth list`
   and selected-provider models with `opencode models "$provider_id" --verbose`.
   Use existing authentication; model listings alone do not prove auth works.
   Resolve the exact `provider/model` and supported reasoning variant without
   substituting a provider or treating model nicknames as portable IDs.
2. **Brief.** Set absolute `project_path`, `brief_path`, and `events_path` values;
   keep the brief and output in a task-specific temporary folder. Include the
   objective, relevant context, write boundaries, Git authorization, acceptance
   criteria, and required report. A new CLI session has no parent conversation.
3. **Run.** With `model_id` set to the selected provider/model:

   ```bash
   opencode run "Follow the attached worker brief." --dir "$project_path" \
     --model "$model_id" --format json --auto --file "$brief_path" > "$events_path"
   ```

   Add `--variant "$effort"` only for a selected, supported model variant; variants
   are provider-specific. Omit model/variant only when the caller explicitly chose
   CLI defaults. `--auto` approves permissions not explicitly denied; it retains
   configured denials. Use it only where supported and allowed by the host. For
   restricted execution, omit it and preserve the caller's permission settings.
   A permission failure is a blocker, not permission to weaken configured rules.
4. **Collect.** Capture the process handle and returned session ID from JSON
   events. Wait for exit, inspect error events and the completed response, and
   return session ID, artifact paths, evidence, and unresolved items. A successful
   launch or exit alone does not prove acceptance.

For related follow-ups, read [session reuse](references/sessions.md). If installed
flags differ, consult [CLI documentation](https://opencode.ai/docs/cli/) and
[permission configuration](https://opencode.ai/docs/permissions/) before adapting.
