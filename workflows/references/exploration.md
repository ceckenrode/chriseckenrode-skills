# Internal exploration

Use small workers to absorb context-heavy navigation and return anchored evidence,
preserving the main agent's context for steering and acceptance. Read a tiny known
excerpt directly when delegation would add overhead.

## Dispatch boundary

During an explicitly authorized planning or exploration run, after workflow setup,
the main agent may select bounded read-only explorers without routine model questions.
This allowance does not apply to help or bare invocation. Explorers gather evidence;
the planning owner makes architectural decisions. Implementation, review, and
fixing retain their separately configured roles.

Choose the smallest adequate native model, supported effort, and count within
user constraints and host capacity. Exact lookup needs less capability than tracing
behavior. Pass focused context instead of full history unless history is needed.
Use [agent dispatch](agent-dispatch.md#backend) for fallback; a preferred model
nickname alone does not justify a CLI. If no useful worker is available, read
narrowly where permitted or report the constraint.

## Evidence and stop

Assign independent questions in parallel; explorer count is separate from stage
worker caps. Use the dispatch brief/report contract: file/line anchors, minimal
excerpts, uncertainties, and searched locations for `NOT FOUND`.

Assess reports before relying on them. Reuse workers for follow-ups only where a
material gap prevents the requested answer or plan. Stop when evidence is
sufficient; record unavailable evidence and the sufficiency decision in the ledger.
