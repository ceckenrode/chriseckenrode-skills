# Agent dispatch

## Backend

1. Identify the actual host and available dispatch tools from the current runtime; do not assume this skill runs in Codex, Claude Code, or any particular CLI. Honor an explicitly requested backend. A requested model alone does not imply an external CLI.
2. Otherwise prefer the current host's native subagents: in Claude Code use its native Claude subagents; in Codex use its native subagent tools; in another host use its supported native mechanism. Inspect exposed capabilities rather than assuming tool names or copying another host's schema. Keep dispatch, follow-ups, monitoring, and result collection on that native mechanism.
3. If native dispatch is unavailable or cannot provide the requested worker, choose an installed, authenticated CLI compatible with the user's model/backend constraints. Prefer the current host's CLI when suitable; do not assume Codex or Claude is installed or make either a universal fallback. Read the selected section of [CLI workers](cli-workers.md), check its help, and announce the fallback and reason once. For another CLI, use its available documentation and actual schema instead of inventing flags. If no compatible backend is available, report the blocker.
4. Preserve explicit and inherited models and effort across configured-stage
   dispatch. Resolve the complete workflow configuration before dispatch; do not
   reset an inherited planner, per-stage override, or effort to a runtime
   default. Planning performed by the lead/orchestrator is not dispatched and
   uses its current model and effort only when no explicit or inherited planning
   worker/model is selected. An explicitly named planning model is honored even
   when it matches the current model, and a backend fallback does not authorize a
   model substitution.
   Native task failures, slow work, or permission denials are not by themselves
   reasons to switch backends or bypass host restrictions. See [exploration](exploration.md)
   for the narrow authorized internal read-only gathering contract.

For native calls, inspect the actual tool schema for models, context/fork options, concurrency, and waits. Select a context option compatible with any model override. Agents may inherit history: write for the context they will actually receive.

Spawn with full permissions by default unless the user requests restrictions. Native agents inherit runtime permissions; request full access only through options the tool actually exposes. CLI workers use the full-permission flags documented in their bundled reference. Assignment scope still controls what a worker should do.

Preserve git authorization in every brief: workers do not commit, stage, amend,
tag, or push, and do not write git history, unless the user explicitly requests
those actions. Read-only exploration and review remain read-only.

For implementation briefs, name the explicit shared-contract owner and
integration owner. The integration owner accepts the combined state and runs
combined-state gates; a worker's individual green check is not integration
evidence. If the user stops or redirects the run, stop affected workers, capture
partial changes and evidence, invalidate verification tied to the old contract,
and preserve unrelated work.

For an explicitly requested external provider, use native or otherwise compatible
CLI capabilities with these assignment and completion contracts. A companion adapter
skill may be used only when the user explicitly asks for that skill; it is never a
prerequisite. Discover actual provider, model, authentication, and command support;
do not invent flags or silently substitute an unavailable backend.

## Brief

Write detailed outbound briefs and request distilled inbound reports. Save context by selecting relevant material, not by compressing away instructions a weaker model needs. Use this structure:

```text
Objective: concrete question or deliverable and why it matters.
Context: project path, current stage/round handoff to read, relevant plan sections and decisions.
Scope: read-only or writable files/modules; constraints and exclusions.
Approach: ordered steps, chosen design and rationale, existing patterns to reuse.
Acceptance: required behavior or questions; exact copy/interfaces where binding.
Examples: representative code, input/output cases, or prototype paths where useful.
Validation: relevant checks and what they establish, when applicable.
Checkpoints: when to report progress, what evidence to include, and when to request a decision.
Report: result, evidence, verification, unresolved issues; keep it concise.
```

Workers end every report with one status line: `DONE` (with the evidence requested), `NEEDS_DECISION` (the missing fact or choice, its options, and their consequences), or `NOT FOUND` (where they looked). The status is a claim; the orchestrator judges the evidence before releasing dependent work.

Give known file/type leads to avoid rediscovery. Link long plans and identify relevant sections. For implementers, include the exact assigned requirements, binding examples/interfaces, and verification gates. Leave only mechanical choices open for implementers; ask them to report missing design decisions with evidence and options instead of guessing. A selected planning worker is explicitly authorized to make the plan's architectural decisions within the accepted scope and must record the rationale; reviewers and fixers follow the settled plan unless an accepted finding routes a plan correction back to its planning owner.

For weaker models, spell out behavior that a stronger implementer might infer: boundary/error cases, ordering, cleanup/lifecycle obligations, exact user-visible states, and which existing abstraction should own the change. Explain the reason for non-obvious constraints so the worker preserves the intent when local details differ. Before dispatch, check that an implementation brief can be followed without inventing a missing design decision; a selected planning brief may leave architectural choices to the planning worker within the accepted scope.

Investigators and reviewers are read-only. Request file/line anchors, minimal supporting excerpts, and material uncertainties. A `NOT FOUND` report should include where the worker looked; assess the evidence before deciding on another search or model.

## Coordination

Parallelize independent assignments within available slots. Give writers disjoint ownership; sequence shared contracts and dependencies. Reconcile unexpected overlap before further edits, preserving unrelated work.

While workers run, synthesize findings, refine decisions, prepare the next brief, or use event waits/bounded status checks. Track worker/session ID, backend, ownership, current milestone, status, and result. Related follow-ups receive the delta and relevant failure evidence.

## Active supervision

For substantial or uncertain assignments, choose checkpoints before expensive dependent work, after the first representative implementation, and at verification. A short bounded assignment may report only at completion. Ask for the current milestone, changed artifacts, evidence so far, next action, and blockers; checkpoints report progress without requiring approval for every mechanical step.

Read progress events and use bounded status checks when a milestone is overdue or there is no useful visibility. Look for repeated rediscovery, unexplained delays, scope expansion, guessed interfaces, contradictory decisions, weak tests, or claims unsupported by results. Distinguish an active long-running check from a stalled worker before intervening.

When work drifts, send a concrete correction: the mismatch and evidence, intended behavior, exact next change, and the gate that will establish it. Resolve design questions promptly. Pause affected workers when continuing would compound a wrong assumption; keep independent work moving. If a corrected brief still fails, split or reassign the task, changing model only within the user's routing constraints.

Before accepting a result, compare it with the brief and the lead's quality standard. Request focused code/diff excerpts, demonstrated behavior, or gate output for material uncertainties. Direct fixes for evidenced gaps; a plausible summary or green tests alone may not establish the intended design or user experience. This is ordinary supervision and acceptance, not an automatic independent review loop.

On failure, distinguish missing context, environment trouble, and task difficulty. Delegate any needed diagnosis, then tighten the brief, split work, or change model when permitted. Retry with new information; report a concrete blocker when progress requires unavailable input.
